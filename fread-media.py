#!/usr/bin/env python3
"""fread-media.py — image and PDF reading engine for fread.

Subcommands:
  probe PATH              — detect type, format, backend; no extraction
  image PATH [opts]       — extract image data (base64 or meta)
  pdf   PATH [opts]       — extract PDF text, render pages, or meta

Output: JSON to stdout. Diagnostics to stderr.
"""

import argparse
import base64
import datetime
import hashlib
import io
import json
import os
import shutil
import struct
import subprocess
import sys

# ── Backend probe ─────────────────────────────────────────────────────────────

try:
    import fitz  # PyMuPDF
    BACKEND_PDF = "pymupdf"
except ImportError:
    fitz = None
    _force = os.environ.get("FREAD_MEDIA_FORCE_BACKEND", "").lower()
    if _force == "pymupdf":
        BACKEND_PDF = "pymupdf"  # will fail at use time; error emitted then
    elif shutil.which("pdftotext") and shutil.which("pdftoppm"):
        BACKEND_PDF = "poppler"
    else:
        BACKEND_PDF = None

try:
    from PIL import Image as _PilImage
    BACKEND_IMAGE = "pillow"
except ImportError:
    _PilImage = None
    BACKEND_IMAGE = "stdlib"


def _effective_pdf_backend():
    """Return (effective_backend, requested_backend) honoring env override."""
    force = os.environ.get("FREAD_MEDIA_FORCE_BACKEND", "").lower()
    if force == "pymupdf":
        if fitz is None:
            return None, "pymupdf"
        return "pymupdf", "pymupdf"
    if force == "poppler":
        if shutil.which("pdftotext") and shutil.which("pdftoppm"):
            return "poppler", "poppler"
        return None, "poppler"
    return BACKEND_PDF, BACKEND_PDF


# ── Magic-byte detection ──────────────────────────────────────────────────────

def detect_format(head: bytes) -> str:
    """Detect file format from magic bytes. Returns format string or 'unknown'."""
    if head[:4] == b'\x89PNG':
        return "png"
    if head[:3] == b'\xff\xd8\xff':
        return "jpeg"
    if head[:6] in (b'GIF87a', b'GIF89a'):
        return "gif"
    if head[:4] == b'RIFF' and head[8:12] == b'WEBP':
        return "webp"
    if head[:4] == b'%PDF':
        return "pdf"
    return "unknown"


IMAGE_FORMATS = frozenset({"png", "jpeg", "gif", "webp"})
IMAGE_MIME = {
    "png": "image/png",
    "jpeg": "image/jpeg",
    "gif": "image/gif",
    "webp": "image/webp",
}


# ── Utility ───────────────────────────────────────────────────────────────────

def file_sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def iso_mtime(path: str) -> str:
    mtime = os.path.getmtime(path)
    return datetime.datetime.fromtimestamp(mtime, tz=datetime.timezone.utc).isoformat()


def tokens_from_b64(data: bytes) -> int:
    """Estimate LLM token cost from raw bytes (base64 expands ~4/3, then /8 per token)."""
    return int(len(base64.b64encode(data)) * 0.125)


def tokens_from_text(text: str) -> int:
    return max(1, len(text) // 4)


def build_ingest_payload(
    path: str, fmt: str, kind: str, summary_text: str, extra: dict
) -> dict:
    sha = file_sha256(path)
    size = os.path.getsize(path)
    mtime = iso_mtime(path)
    basename = os.path.basename(path)
    ext = os.path.splitext(basename)[1].lstrip(".") or fmt

    tags = ["fread", "media", f"format:{fmt}", f"ext:{ext}", f"hash:{sha[:12]}"]
    mem_type = "long_term" if kind == "pdf-text" else "short_term"

    lines = [
        f"Path: {os.path.abspath(path)}",
        f"Format: {fmt}",
        f"Bytes: {size}",
    ]
    if "page_count" in extra:
        lines.append(f"Pages: {extra['page_count']}")
    lines += [f"SHA256: {sha}", f"Mtime: {mtime}", "---", summary_text[:500]]

    return {
        "title": f"fread: {basename}",
        "category": "custom",
        "type": mem_type,
        "tags": tags,
        "importance": "low",
        "scope": "project",
        "source": {"type": "agent", "identifier": "fsuite-fread"},
        "content": "\n".join(lines),
    }


def emit(obj: dict, exit_code: int = 0):
    json.dump(obj, sys.stdout)
    sys.stdout.write("\n")
    sys.stdout.flush()
    sys.exit(exit_code)


def err(message: str, code: str, exit_code: int = 1):
    emit({"type": "error", "error": message, "code": code}, exit_code)


# ── PyMuPDF backend ───────────────────────────────────────────────────────────

class PyMuPDFBackend:
    def page_count(self, path: str) -> int:
        doc = fitz.open(path)
        n = doc.page_count
        doc.close()
        return n

    def extract_text(self, path: str, pages: list) -> list:
        doc = fitz.open(path)
        results = []
        for i in pages:
            if 0 <= i < doc.page_count:
                results.append(doc[i].get_text())
            else:
                results.append("")
        doc.close()
        return results

    def render_page(self, path: str, page: int, dpi: int = 100) -> bytes:
        doc = fitz.open(path)
        pix = doc[page].get_pixmap(dpi=dpi)
        data = pix.tobytes("jpeg")
        doc.close()
        return data

    def get_page_dims(self, path: str, page: int) -> dict:
        doc = fitz.open(path)
        r = doc[page].rect
        doc.close()
        return {"width": round(r.width, 2), "height": round(r.height, 2)}

    def metadata(self, path: str) -> dict:
        doc = fitz.open(path)
        pc = doc.page_count
        encrypted = doc.is_encrypted
        page_size = {}
        if pc > 0:
            r = doc[0].rect
            page_size = {"width": round(r.width, 2), "height": round(r.height, 2)}
        has_text = False
        img_count = 0
        for pg in doc:
            if pg.get_text().strip():
                has_text = True
            img_count += len(pg.get_images())
        doc.close()
        return {
            "page_count": pc,
            "encrypted": encrypted,
            "has_text": has_text,
            "embedded_image_count": img_count,
            "page_size": page_size,
            "mtime": iso_mtime(path),
        }


# ── Poppler backend ───────────────────────────────────────────────────────────

class PopplerBackend:
    def page_count(self, path: str) -> int:
        try:
            out = subprocess.check_output(
                ["pdfinfo", path], stderr=subprocess.DEVNULL, text=True
            )
            for line in out.splitlines():
                if line.startswith("Pages:"):
                    return int(line.split(":", 1)[1].strip())
        except Exception:
            pass
        return 0

    def extract_text(self, path: str, pages: list) -> list:
        results = []
        for i in pages:
            p = i + 1  # pdftotext is 1-indexed
            try:
                out = subprocess.check_output(
                    ["pdftotext", "-f", str(p), "-l", str(p), path, "-"],
                    stderr=subprocess.DEVNULL,
                )
                results.append(out.decode("utf-8", errors="replace"))
            except Exception:
                results.append("")
        return results

    def render_page(self, path: str, page: int, dpi: int = 100) -> bytes:
        import tempfile
        p = page + 1  # pdftoppm is 1-indexed
        with tempfile.TemporaryDirectory() as tmp:
            prefix = os.path.join(tmp, "pg")
            subprocess.check_call(
                ["pdftoppm", "-jpeg", "-r", str(dpi), "-f", str(p), "-l", str(p),
                 path, prefix],
                stderr=subprocess.DEVNULL,
            )
            files = sorted(f for f in os.listdir(tmp) if f.endswith(".jpg"))
            if not files:
                raise RuntimeError(f"pdftoppm produced no output for page {p}")
            with open(os.path.join(tmp, files[0]), "rb") as f:
                return f.read()

    def get_page_dims(self, path: str, page: int) -> dict:
        # pdfinfo gives page size in points for all pages — not per-page easily
        return {}

    def metadata(self, path: str) -> dict:
        pc = self.page_count(path)
        has_text = False
        try:
            out = subprocess.check_output(
                ["pdftotext", "-f", "1", "-l", "1", path, "-"],
                stderr=subprocess.DEVNULL,
            )
            has_text = bool(out.strip())
        except Exception:
            pass
        page_size = {}
        try:
            out = subprocess.check_output(
                ["pdfinfo", path], stderr=subprocess.DEVNULL, text=True
            )
            for line in out.splitlines():
                if line.startswith("Page size:"):
                    parts = line.split(":", 1)[1].strip().split()
                    if len(parts) >= 3:
                        try:
                            page_size = {
                                "width": float(parts[0]),
                                "height": float(parts[2]),
                            }
                        except ValueError:
                            pass
        except Exception:
            pass
        return {
            "page_count": pc,
            "encrypted": False,
            "has_text": has_text,
            "embedded_image_count": 0,
            "page_size": page_size,
            "mtime": iso_mtime(path),
        }


def get_pdf_backend():
    effective, requested = _effective_pdf_backend()
    if effective is None:
        if requested:
            err(
                f"Forced backend '{requested}' is not available. "
                "Install PyMuPDF (pip install pymupdf) or "
                "Poppler (apt install poppler-utils).",
                "BACKEND_MISSING",
            )
        else:
            err(
                "No PDF backend available. "
                "Install PyMuPDF (pip install pymupdf) or "
                "Poppler (apt install poppler-utils).",
                "BACKEND_MISSING",
            )
    if effective == "pymupdf":
        return PyMuPDFBackend(), "pymupdf"
    return PopplerBackend(), "poppler"


# ── Image resize loop ─────────────────────────────────────────────────────────

def fit_to_token_budget(img, target_format: str, max_tokens: int):
    """Iteratively resize/compress image to fit within max_tokens.

    Halves dimensions at each step, tries JPEG quality 90 → 70 → 50.
    Returns (encoded_bytes, info_dict).
    """
    from PIL import Image
    resized = False
    current = img.copy()

    for quality in (90, 70, 50):
        buf = io.BytesIO()
        use_jpeg = target_format in ("jpeg", "webp", "gif")
        if use_jpeg:
            current.convert("RGB").save(buf, format="JPEG", quality=quality)
        else:
            current.save(buf, format="PNG", optimize=True)
        data = buf.getvalue()
        if tokens_from_b64(data) <= max_tokens:
            w, h = current.size
            return data, {
                "width": w, "height": h,
                "quality": quality if use_jpeg else None,
                "resized": resized,
            }
        # Halve and loop
        new_w = max(1, current.width // 2)
        new_h = max(1, current.height // 2)
        current = current.resize((new_w, new_h), Image.LANCZOS)
        resized = True

    # Final attempt
    buf = io.BytesIO()
    use_jpeg = target_format in ("jpeg", "webp", "gif")
    if use_jpeg:
        current.convert("RGB").save(buf, format="JPEG", quality=50)
    else:
        current.save(buf, format="PNG", optimize=True)
    data = buf.getvalue()
    w, h = current.size
    return data, {"width": w, "height": h, "quality": 50 if use_jpeg else None, "resized": resized}


# ── Probe subcommand ──────────────────────────────────────────────────────────

def cmd_probe(args):
    path = args.path
    if not os.path.isfile(path):
        err(f"File not found: {path}", "FILE_NOT_FOUND")

    size = os.path.getsize(path)
    with open(path, "rb") as f:
        head = f.read(16)
    fmt = detect_format(head)

    if fmt == "pdf":
        detected = "pdf"
        effective, _ = _effective_pdf_backend()
        would_use = effective if effective else "none"
    elif fmt in IMAGE_FORMATS:
        detected = "image"
        would_use = BACKEND_IMAGE
    else:
        detected = "unknown"
        would_use = "none"

    emit({
        "type": "probe",
        "detected": detected,
        "format": fmt,
        "size": size,
        "would_use_backend": would_use,
    })


# ── Image subcommand ──────────────────────────────────────────────────────────

def _stdlib_dimensions(path: str, fmt: str):
    """Parse image dimensions without Pillow."""
    with open(path, "rb") as f:
        data = f.read(256)
    if fmt == "png" and len(data) >= 24:
        w, h = struct.unpack(">II", data[16:24])
        return w, h
    if fmt == "jpeg":
        i = 2
        while i < len(data) - 8:
            if data[i] != 0xFF:
                break
            marker = data[i + 1]
            if i + 4 > len(data):
                break
            length = struct.unpack(">H", data[i + 2:i + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3) and i + 9 <= len(data):
                h, w = struct.unpack(">HH", data[i + 5:i + 9])
                return w, h
            i += 2 + length
    return 0, 0


def cmd_image(args):
    path = args.path
    if not os.path.isfile(path):
        err(f"File not found: {path}", "FILE_NOT_FOUND")

    size = os.path.getsize(path)
    with open(path, "rb") as f:
        head = f.read(16)
    fmt = detect_format(head)

    if fmt not in IMAGE_FORMATS:
        err(
            f"Unsupported image format '{fmt}' detected from magic bytes. "
            "Supported: png, jpeg, gif, webp.",
            "UNSUPPORTED_FORMAT",
        )

    mime_type = IMAGE_MIME[fmt]

    # ── meta-only ──────────────────────────────────────────────────────────────
    if args.meta_only:
        if BACKEND_IMAGE == "pillow":
            from PIL import Image
            with Image.open(path) as img:
                w, h = img.size
        else:
            w, h = _stdlib_dimensions(path, fmt)
        emit({
            "type": "image-meta",
            "file": {
                "format": fmt,
                "dimensions": {"width": w, "height": h},
                "original_size": size,
                "mtime": iso_mtime(path),
            },
            "backend": BACKEND_IMAGE,
        })

    # ── full extraction with Pillow ────────────────────────────────────────────
    if BACKEND_IMAGE == "pillow":
        from PIL import Image
        with Image.open(path) as img:
            orig_w, orig_h = img.size
            img_copy = img.copy()

        if args.no_resize:
            with open(path, "rb") as f:
                raw = f.read()
            estimate = tokens_from_b64(raw)
            if estimate > args.max_tokens:
                err(
                    f"Raw image token estimate ({estimate}) exceeds budget ({args.max_tokens}). "
                    "Remove --no-resize to allow automatic resizing.",
                    "TOKEN_BUDGET_EXCEEDED",
                )
            b64 = base64.b64encode(raw).decode("ascii")
            ingest_summary = f"Image {fmt} {orig_w}x{orig_h}, {size} bytes"
            emit({
                "type": "image",
                "file": {
                    "base64": b64,
                    "mime_type": mime_type,
                    "format": fmt,
                    "original_size": size,
                    "dimensions": {"width": orig_w, "height": orig_h},
                    "resized": False,
                    "tokens_estimate": estimate,
                },
                "backend": BACKEND_IMAGE,
                "ingest_payload": build_ingest_payload(
                    path, fmt, "image", ingest_summary, {}
                ),
            })

        # Default: fit to token budget
        encoded, info = fit_to_token_budget(img_copy, fmt, args.max_tokens)
        b64 = base64.b64encode(encoded).decode("ascii")
        estimate = tokens_from_b64(encoded)
        use_jpeg = fmt in ("jpeg", "webp", "gif")
        out_mime = "image/jpeg" if (use_jpeg or info.get("quality") is not None) else mime_type
        ingest_summary = f"Image {fmt} {orig_w}x{orig_h}, {size} bytes"
        emit({
            "type": "image",
            "file": {
                "base64": b64,
                "mime_type": out_mime,
                "format": fmt,
                "original_size": size,
                "dimensions": {"width": info["width"], "height": info["height"]},
                "resized": info["resized"],
                "tokens_estimate": estimate,
            },
            "backend": BACKEND_IMAGE,
            "ingest_payload": build_ingest_payload(
                path, fmt, "image", ingest_summary, {}
            ),
        })

    # ── stdlib fallback ────────────────────────────────────────────────────────
    with open(path, "rb") as f:
        raw = f.read()
    estimate = tokens_from_b64(raw)
    if estimate > args.max_tokens and not args.no_resize:
        err(
            f"Pillow not installed; cannot resize. "
            f"Token estimate {estimate} exceeds budget {args.max_tokens}. "
            "Install Pillow (pip install pillow) for resize support.",
            "BACKEND_MISSING",
        )
    w, h = _stdlib_dimensions(path, fmt)
    b64 = base64.b64encode(raw).decode("ascii")
    ingest_summary = f"Image {fmt} {w}x{h}, {size} bytes"
    emit({
        "type": "image",
        "file": {
            "base64": b64,
            "mime_type": mime_type,
            "format": fmt,
            "original_size": size,
            "dimensions": {"width": w, "height": h},
            "resized": False,
            "tokens_estimate": estimate,
        },
        "backend": BACKEND_IMAGE,
        "ingest_payload": build_ingest_payload(path, fmt, "image", ingest_summary, {}),
    })


# ── PDF subcommand ────────────────────────────────────────────────────────────

def _parse_page_range(pages_str: str, total: int) -> list:
    """Parse 'X:Y' (1-indexed, inclusive) into 0-indexed list."""
    if not pages_str:
        return list(range(total))
    parts = pages_str.split(":")
    try:
        lo = max(1, int(parts[0]))
        hi = int(parts[1]) if len(parts) > 1 and parts[1] else total
    except ValueError:
        return list(range(total))
    hi = min(hi, total)
    return list(range(lo - 1, hi))


def cmd_pdf(args):
    path = args.path
    if not os.path.isfile(path):
        err(f"File not found: {path}", "FILE_NOT_FOUND")

    with open(path, "rb") as f:
        head = f.read(8)
    fmt = detect_format(head)
    if fmt != "pdf":
        err(
            f"File does not appear to be a PDF (magic bytes: {head[:4]!r}).",
            "UNSUPPORTED_FORMAT",
        )

    backend, backend_name = get_pdf_backend()
    size = os.path.getsize(path)
    total_pages = backend.page_count(path)

    # ── meta-only ──────────────────────────────────────────────────────────────
    if args.meta_only:
        meta = backend.metadata(path)
        emit({"type": "pdf-meta", "file": meta, "backend": backend_name})

    # ── render mode ───────────────────────────────────────────────────────────
    if args.render:
        pages_str = args.pages or "1:5"
        page_indices = _parse_page_range(pages_str, total_pages)

        if len(page_indices) > 10 and args.max_pages is None:
            err(
                f"Render would cover {len(page_indices)} pages. "
                "Pass --max-pages N to allow more than 10 rendered pages.",
                "TOKEN_BUDGET_EXCEEDED",
            )

        if args.max_pages is not None:
            page_indices = page_indices[: args.max_pages]

        pages_out = []
        for i in page_indices:
            jpeg_bytes = backend.render_page(path, i, dpi=100)
            b64 = base64.b64encode(jpeg_bytes).decode("ascii")
            estimate = tokens_from_b64(jpeg_bytes)
            dims = backend.get_page_dims(path, i)
            pages_out.append({
                "page": i + 1,
                "base64": b64,
                "mime_type": "image/jpeg",
                "dimensions": dims,
                "tokens_estimate": estimate,
            })

        ingest_summary = f"PDF rendered {len(pages_out)} page(s) as JPEG, {size} bytes"
        emit({
            "type": "pdf-pages",
            "file": {
                "page_count": total_pages,
                "count": len(pages_out),
                "pages": pages_out,
                "original_size": size,
            },
            "backend": backend_name,
            "ingest_payload": build_ingest_payload(
                path, "pdf", "pdf-pages", ingest_summary,
                {"page_count": total_pages},
            ),
        })

    # ── default: text extraction ───────────────────────────────────────────────
    pages_str = args.pages or None
    if pages_str:
        page_indices = _parse_page_range(pages_str, total_pages)
    else:
        page_indices = list(range(total_pages))

    per_page_cap_tokens = 5000
    total_cap_tokens = args.token_budget

    raw_texts = backend.extract_text(path, page_indices)

    assembled_parts = []
    total_tokens = 0
    pages_returned = []
    truncated = False

    for pg_idx, text in zip(page_indices, raw_texts):
        pg_tokens = tokens_from_text(text)
        # Enforce per-page cap
        if pg_tokens > per_page_cap_tokens:
            text = text[: per_page_cap_tokens * 4]
            pg_tokens = per_page_cap_tokens
        # Enforce total cap
        if total_tokens + pg_tokens > total_cap_tokens:
            remaining = total_cap_tokens - total_tokens
            if remaining > 0:
                text = text[: remaining * 4]
                assembled_parts.append(f"--- page {pg_idx + 1} ---\n{text}")
                pages_returned.append(pg_idx + 1)
            truncated = True
            break
        assembled_parts.append(f"--- page {pg_idx + 1} ---\n{text}")
        pages_returned.append(pg_idx + 1)
        total_tokens += pg_tokens

    joined_text = "\n".join(assembled_parts)

    # Ingest summary: first ~500 chars of plain text, stripping separators
    plain = joined_text.replace("\n", " ")
    plain = " ".join(w for w in plain.split() if not w.startswith("---"))
    ingest_summary = plain[:500] if plain.strip() else "<no extractable text — image-only PDF>"

    emit({
        "type": "pdf-text",
        "file": {
            "page_count": total_pages,
            "pages_returned": pages_returned,
            "text": joined_text,
            "tokens_estimate": tokens_from_text(joined_text),
            "truncated": truncated,
        },
        "backend": backend_name,
        "ingest_payload": build_ingest_payload(
            path, "pdf", "pdf-text", ingest_summary,
            {"page_count": total_pages},
        ),
    })


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="fread-media — image and PDF reading engine"
    )
    sub = parser.add_subparsers(dest="command")

    # probe
    p_probe = sub.add_parser("probe", help="Detect type and backend; no extraction")
    p_probe.add_argument("path")

    # image
    p_img = sub.add_parser("image", help="Extract image data or metadata")
    p_img.add_argument("path")
    p_img.add_argument(
        "--meta-only", action="store_true",
        help="Return dimensions/format/size only, no base64",
    )
    p_img.add_argument(
        "--no-resize", action="store_true",
        help="Emit raw base64; refuse if over token budget",
    )
    p_img.add_argument(
        "--max-tokens", type=int, default=6000, metavar="N",
        help="Token budget for image output (default: 6000)",
    )

    # pdf
    p_pdf = sub.add_parser("pdf", help="Extract PDF text, render pages, or metadata")
    p_pdf.add_argument("path")
    p_pdf.add_argument(
        "--render", action="store_true",
        help="Rasterize pages to JPEG base64 instead of extracting text",
    )
    p_pdf.add_argument(
        "--meta-only", action="store_true",
        help="Return page count, size, encryption flag, etc.",
    )
    p_pdf.add_argument(
        "--pages", metavar="X:Y", default=None,
        help="Page range (1-indexed, inclusive). E.g. '1:3'",
    )
    p_pdf.add_argument(
        "--max-pages", type=int, default=None, metavar="N",
        help="Allow render past 10 pages; sets the cap",
    )
    p_pdf.add_argument(
        "--token-budget", type=int, default=25000, metavar="N",
        help="Total token cap for text extraction (default: 25000)",
    )

    args = parser.parse_args()

    if not args.command:
        parser.print_help(sys.stderr)
        sys.exit(1)

    try:
        if args.command == "probe":
            cmd_probe(args)
        elif args.command == "image":
            cmd_image(args)
        elif args.command == "pdf":
            cmd_pdf(args)
    except SystemExit:
        raise
    except Exception as exc:
        import traceback as _tb
        json.dump(
            {
                "type": "error",
                "error": str(exc),
                "code": "INTERNAL_ERROR",
                "traceback": _tb.format_exc(),
            },
            sys.stdout,
        )
        sys.stdout.write("\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
