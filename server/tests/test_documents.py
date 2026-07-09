"""Tests for PDF/DOCX/PPTX document generation."""

from __future__ import annotations

from vesnai.ai.documents import DocumentSection, DocumentService, DocumentSlide, StructuredDocument
from vesnai.providers.fakes import FakeAIProvider


def test_generate_pdf_magic_bytes():
    doc_service = DocumentService(FakeAIProvider())
    doc = StructuredDocument(
        title="Test",
        sections=[DocumentSection(heading="H", body="Body", bullets=["x"])],
    )
    data, mime, ext = doc_service.render("pdf", doc)
    assert ext == ".pdf"
    assert mime == "application/pdf"
    assert data.startswith(b"%PDF")


def test_generate_docx_magic_bytes():
    doc_service = DocumentService(FakeAIProvider())
    doc = StructuredDocument(
        title="Test",
        sections=[DocumentSection(heading="H", body="Body")],
    )
    data, mime, ext = doc_service.render("docx", doc)
    assert ext == ".docx"
    assert data[:2] == b"PK"


def test_generate_pptx_magic_bytes():
    doc_service = DocumentService(FakeAIProvider())
    doc = StructuredDocument(
        title="Deck",
        slides=[DocumentSlide(title="Slide 1", bullets=["point"])],
    )
    data, mime, ext = doc_service.render("pptx", doc)
    assert ext == ".pptx"
    assert data[:2] == b"PK"


def test_attachment_path_format():
    path = DocumentService.attachment_path("abc12345", ".pdf")
    assert path.startswith("attachments/abc12345-doc-")
    assert path.endswith(".pdf")
