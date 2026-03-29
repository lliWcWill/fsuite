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


def scan_pattern(data, pattern, context=300, ignore_case=False):
    """Find all occurrences of a literal byte pattern with surrounding context."""
    if ignore_case:
        flags = re.IGNORECASE
        pat = re.compile(re.escape(pattern.encode("utf-8", errors="replace")), flags)
    else:
        pat = re.compile(re.escape(pattern.encode("utf-8", errors="replace")))

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
    p_scan.add_argument("--pattern", required=True)
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

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    file_path = args.file
    if not os.path.exists(file_path):
        json.dump({"error": f"file not found: {file_path}"}, sys.stdout)
        sys.exit(1)

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
                results = scan_pattern(data, args.pattern, args.context, args.ignore_case)
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
