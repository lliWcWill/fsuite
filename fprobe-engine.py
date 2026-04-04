#!/usr/bin/env python3
"""fprobe-engine.py — byte-safe reconnaissance engine for fprobe.

Reads opaque/binary files and extracts printable strings, scans for
literal patterns with context, and windows into arbitrary byte offsets.

All heavy lifting lives here; the bash entrypoint handles CLI parsing
and output formatting.

Output: JSON to stdout. Pretty formatting is the bash layer's job.
"""

import sys
import json
import mmap
import os
import re
import argparse


def resolve_bytes(text_value=None, hex_value=None, field_name="value"):
    """Resolve either a UTF-8 text arg or a hidden hex arg into raw bytes."""
    if hex_value is not None:
        try:
            return bytes.fromhex(hex_value)
        except ValueError as exc:
            raise ValueError(f"{field_name}_hex is not valid hex") from exc
    if text_value is None:
        return None
    return text_value.encode("utf-8", errors="replace")


def extract_strings(data, min_length=6):
    """Extract printable ASCII strings of at least min_length from raw bytes."""
    pattern = re.compile(rb'[\x20-\x7e]{%d,}' % min_length)
    results = []
    for m in pattern.finditer(data):
        results.append({
            "offset": m.start(),
            "length": m.end() - m.start(),
            "text": m.group().decode("ascii", errors="replace"),
        })
    return results


def filter_strings(strings, needle, ignore_case=False, context=200):
    """Filter extracted strings to those containing needle.
    
    Long strings are trimmed to a window of `context` chars around each match
    so results stay usable on real binaries (where a single printable run
    can be 50KB+).
    """
    results = []
    needle_cmp = needle.lower() if ignore_case else needle
    for s in strings:
        text = s["text"]
        text_cmp = text.lower() if ignore_case else text
        idx = text_cmp.find(needle_cmp)
        if idx == -1:
            continue
        # Short string — return as-is
        if len(text) <= context * 2 + len(needle):
            results.append(s)
            continue
        # Long string — trim to window around match
        win_start = max(0, idx - context)
        win_end = min(len(text), idx + len(needle) + context)
        trimmed = text[win_start:win_end]
        results.append({
            "offset": s["offset"] + win_start,
            "length": win_end - win_start,
            "text": trimmed,
            "trimmed_from": s["length"],
        })
    return results


def scan_pattern(data, pattern=None, context=300, ignore_case=False, pattern_hex=None):
    """Find all occurrences of a literal byte pattern with surrounding context."""
    pattern_bytes = resolve_bytes(pattern, pattern_hex, "pattern")
    if pattern_bytes is None:
        raise ValueError("scan_pattern requires at least one of pattern or pattern_hex")
    if ignore_case:
        flags = re.IGNORECASE
        pat = re.compile(re.escape(pattern_bytes), flags)
    else:
        pat = re.compile(re.escape(pattern_bytes))

    results = []
    for m in pat.finditer(data):
        start = max(0, m.start() - context)
        end = min(len(data), m.end() + context)
        chunk = data[start:end]
        # Replace non-printable bytes with dots for readability
        printable = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        results.append({
            "offset": m.start(),
            "match_length": m.end() - m.start(),
            "context_start": start,
            "context_end": end,
            "text": printable,
        })
    return results


def patch_binary(file_path, target_str=None, replacement_str=None, dry_run=False, target_hex=None, replacement_hex=None):
    """Find and replace a byte pattern in a binary file. Same-length enforced."""
    target = resolve_bytes(target_str, target_hex, "target")
    replacement = resolve_bytes(replacement_str, replacement_hex, "replacement")
    write_path = os.path.realpath(file_path)

    if len(target) == 0:
        return {"error": "target pattern must not be empty", "patched": 0}

    if len(replacement) > len(target):
        return {"error": f"replacement ({len(replacement)} bytes) exceeds target ({len(target)} bytes)", "patched": 0}
    # Pad replacement with spaces to match target length
    if len(replacement) < len(target):
        replacement = replacement + b" " * (len(target) - len(replacement))

    with open(write_path, "rb") as f:
        data = bytearray(f.read())

    file_size = len(data)
    offsets = []
    pos = 0
    while True:
        idx = data.find(target, pos)
        if idx == -1:
            break
        offsets.append(idx)
        if not dry_run:
            data[idx:idx + len(target)] = replacement
        pos = idx + len(target)

    if not offsets:
        return {
            "patched": 0,
            "dry_run": dry_run,
            "target_size": len(target),
            "file_size": file_size,
            "error": "target pattern not found",
        }

    backup_path = None
    if not dry_run and offsets:
        backup_path = write_path + ".bak"
        if not os.path.exists(backup_path):
            import shutil
            shutil.copy2(write_path, backup_path)
        # Write via temp file + rename to handle "Text file busy"
        tmp_path = write_path + ".fprobe-tmp"
        try:
            with open(tmp_path, "wb") as f:
                f.write(data)
            os.chmod(tmp_path, os.stat(write_path).st_mode)
            os.replace(tmp_path, write_path)
        except Exception:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
            raise

    return {
        "patched": len(offsets),
        "offsets": offsets,
        "dry_run": dry_run,
        "target_size": len(target),
        "replacement_size": len(replacement),
        "file_size": file_size,
        "backup": backup_path,
    }


def read_window(data, offset, before=0, after=200, decode="printable"):
    """Read a window of bytes around a given offset."""
    file_size = len(data)
    start = max(0, offset - before)
    end = min(file_size, offset + after)

    if start >= file_size:
        return {
            "offset": offset,
            "start": start,
            "end": end,
            "file_size": file_size,
            "error": "offset beyond file size",
            "text": "",
        }

    chunk = data[start:end]

    if decode == "hex":
        text = " ".join(f"{b:02x}" for b in chunk)
    elif decode == "utf8":
        text = chunk.decode("utf-8", errors="replace")
    else:  # printable
        text = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)

    return {
        "offset": offset,
        "start": start,
        "end": end,
        "length": end - start,
        "file_size": file_size,
        "decode": decode,
        "text": text,
    }


def main():
    parser = argparse.ArgumentParser(description="fprobe engine — binary reconnaissance")
    sub = parser.add_subparsers(dest="command")

    # strings
    p_str = sub.add_parser("strings")
    p_str.add_argument("file")
    p_str.add_argument("--filter", default=None)
    p_str.add_argument("--ignore-case", action="store_true")
    p_str.add_argument("--min-length", type=int, default=6)

    # scan
    p_scan = sub.add_parser("scan")
    p_scan.add_argument("file")
    p_scan.add_argument("--pattern")
    p_scan.add_argument("--pattern-hex", help=argparse.SUPPRESS)
    p_scan.add_argument("--context", type=int, default=300)
    p_scan.add_argument("--ignore-case", action="store_true")

    # window
    def nonneg_int(x):
        i = int(x)
        if i < 0:
            raise argparse.ArgumentTypeError(f"{x} must be >= 0")
        return i

    p_win = sub.add_parser("window")
    p_win.add_argument("file")
    p_win.add_argument("--offset", type=nonneg_int, required=True)
    p_win.add_argument("--before", type=nonneg_int, default=0)
    p_win.add_argument("--after", type=nonneg_int, default=200)
    p_win.add_argument("--decode", choices=["printable", "utf8", "hex"], default="printable")

    # patch
    p_patch = sub.add_parser("patch")
    p_patch.add_argument("file")
    p_patch.add_argument("--target", help="Literal text to find in binary")
    p_patch.add_argument("--target-hex", help=argparse.SUPPRESS)
    p_patch.add_argument("--replacement", help="Replacement text (padded with spaces if shorter)")
    p_patch.add_argument("--replacement-hex", help=argparse.SUPPRESS)
    p_patch.add_argument("--dry-run", action="store_true", help="Show what would be patched without writing")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    file_path = args.file
    if not os.path.exists(file_path):
        json.dump({"error": f"file not found: {file_path}"}, sys.stdout)
        sys.exit(1)

    if args.command == "scan":
        if args.pattern is None and args.pattern_hex is None:
            json.dump({"error": "scan requires --pattern"}, sys.stdout)
            sys.exit(1)

    # patch handles its own file I/O (needs write access)
    if args.command == "patch":
        if args.target is None and args.target_hex is None:
            json.dump({"error": "patch requires --target", "patched": 0}, sys.stdout)
            sys.exit(1)
        if args.replacement is None and args.replacement_hex is None:
            json.dump({"error": "patch requires --replacement", "patched": 0}, sys.stdout)
            sys.exit(1)
        result = patch_binary(
            file_path,
            args.target,
            args.replacement,
            args.dry_run,
            target_hex=args.target_hex,
            replacement_hex=args.replacement_hex,
        )
        json.dump(result, sys.stdout)
        sys.exit(0 if result["patched"] > 0 else 1)

    file_size = os.path.getsize(file_path)
    if file_size == 0:
        if args.command == "strings":
            json.dump([], sys.stdout)
        elif args.command == "scan":
            json.dump([], sys.stdout)
        elif args.command == "window":
            json.dump({"offset": args.offset, "text": "", "file_size": 0}, sys.stdout)
        sys.exit(0)

    with open(file_path, "rb") as f:
        data = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        try:
            if args.command == "strings":
                results = extract_strings(data, args.min_length)
                if args.filter:
                    results = filter_strings(results, args.filter, args.ignore_case)
                json.dump(results, sys.stdout)

            elif args.command == "scan":
                results = scan_pattern(data, args.pattern, args.context, args.ignore_case, pattern_hex=args.pattern_hex)
                json.dump(results, sys.stdout)

            elif args.command == "window":
                result = read_window(data, args.offset, args.before, args.after, args.decode)
                json.dump(result, sys.stdout)
        finally:
            data.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        json.dump({"error": str(e), "traceback": traceback.format_exc()}, sys.stdout)
        sys.exit(1)
