"""QR-code rendering for device pairing.

The pairing payload is a small JSON blob ``{"url": ..., "code": ...}`` so the
mobile app can scan a single code to learn both the server URL and the
short-lived pairing code. Rendering is isolated here so it stays unit-testable
and so the optional dependency (``segno``) is imported lazily.
"""

from __future__ import annotations


def qr_svg(data: str) -> str:
    """Return an inline SVG string encoding ``data`` as a QR code."""
    import io

    import segno

    buf = io.BytesIO()
    segno.make(data, error="m").save(buf, kind="svg", scale=4, border=2)
    return buf.getvalue().decode("utf-8")


def qr_ascii(data: str) -> str:
    """Return a terminal-friendly QR code (for printing on server start)."""
    import io

    import segno

    buf = io.StringIO()
    segno.make(data, error="m").terminal(out=buf, border=2)
    return buf.getvalue()
