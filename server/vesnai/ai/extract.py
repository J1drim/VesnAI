"""Attachment text extraction (OCR for images, parsers for PDF/docx).

Heavy extractors (Tesseract, pypdf) are optional imports; when unavailable the
service degrades gracefully and returns empty text. A pluggable ``Extractor``
callable keeps this testable without the native libraries installed.
"""

from __future__ import annotations

from collections.abc import Callable

Extractor = Callable[[bytes, str], str]


def default_extractor(data: bytes, filename: str) -> str:
    name = filename.lower()
    try:
        if name.endswith(".pdf"):
            return _extract_pdf(data)
        if name.endswith((".png", ".jpg", ".jpeg", ".webp", ".tif", ".tiff")):
            return _extract_image_ocr(data)
        if name.endswith((".txt", ".md")):
            return data.decode("utf-8", errors="replace")
    except Exception:  # noqa: BLE001 - extraction is best-effort
        return ""
    return ""


def _extract_pdf(data: bytes) -> str:
    import io

    from pypdf import PdfReader

    reader = PdfReader(io.BytesIO(data))
    return "\n".join((page.extract_text() or "") for page in reader.pages)


def _extract_image_ocr(data: bytes) -> str:
    import io

    import pytesseract
    from PIL import Image

    return pytesseract.image_to_string(Image.open(io.BytesIO(data)))
