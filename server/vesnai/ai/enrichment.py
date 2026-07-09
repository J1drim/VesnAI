"""AI enrichment: generate supplementary, clearly-marked OKF concepts.

- Idea -> an evocative generated image (FLUX in production) to aid memory.
- Photo -> a generated caption/sentence.

Every output is saved as a new OKF concept with ``origin: generated`` and a
back-link to its source, and indexed. Enrichment is idempotent: re-enriching a
source does not create duplicates.
"""

from __future__ import annotations

from vesnai.ai.image_prompts import build_memory_image_prompt
from vesnai.ai.index import IndexService
from vesnai.notes import NoteInput, NoteService
from vesnai.okf.model import Origin
from vesnai.providers.base import (
    AIProvider,
    Clock,
    ImageProvider,
    SystemClock,
    VisionProvider,
)

KIND_IMAGE = "GeneratedImage"
KIND_CAPTION = "GeneratedCaption"

_IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".tif", ".tiff")


class EnrichmentService:
    def __init__(
        self,
        notes: NoteService,
        index: IndexService,
        *,
        image_provider: ImageProvider,
        ai_provider: AIProvider,
        vision_provider: VisionProvider | None = None,
        clock: Clock | None = None,
    ) -> None:
        self.notes = notes
        self.index = index
        self.image_provider = image_provider
        self.ai_provider = ai_provider
        self.vision_provider = vision_provider
        self.clock = clock or SystemClock()

    def _existing_child(self, source_path: str, kind: str) -> str | None:
        for rel, concept in self.notes.list().items():
            if (
                concept.is_generated
                and concept.type == kind
                and concept.source == source_path
            ):
                return rel
        return None

    def enrich_idea(self, source_path: str, *, seed: int = 0) -> str:
        """Generate an evocative image concept for an idea note (idempotent)."""
        existing = self._existing_child(source_path, KIND_IMAGE)
        if existing:
            return existing

        source = self.notes.get(source_path)
        prompt = build_memory_image_prompt(source.title or "", source.body)
        image = self.image_provider.generate(prompt, seed=seed)
        attachment_path = f"attachments/{_stem(source_path)}-generated.png"
        self.notes.store.save_attachment(attachment_path, image.data)

        rel, concept = self.notes.create(
            NoteInput(
                title=f"{source.title} (image)",
                body=(
                    f"Generated to help you remember this idea.\n\n"
                    f"![generated]({_rel_from(attachment_path)})\n\n"
                    f"Linked from [{source.title}]({_rel_from(source_path)})."
                ),
                type=KIND_IMAGE,
                tags=["generated"],
                origin=Origin.GENERATED,
                source=source_path,
                links=[source_path],
                attachments=[attachment_path],
            )
        )
        self._link_back(source_path, rel)
        self.index.index_concept(rel, concept)
        return rel

    def enrich_photo(self, source_path: str) -> str:
        """Generate a caption concept for a photo note (idempotent)."""
        existing = self._existing_child(source_path, KIND_CAPTION)
        if existing:
            return existing

        source = self.notes.get(source_path)
        prompt = (
            "Write a single evocative sentence that captures the feeling of this "
            f"photo titled '{source.title}'. Context: {source.body}"
        )
        image_bytes = self._first_image_attachment(source)
        if self.vision_provider is not None and image_bytes is not None:
            # A real vision model "sees" the photo to caption it.
            caption = self.vision_provider.caption(image_bytes, prompt)
        else:
            # No image attachment (or no vision model): caption from note context.
            caption = self.ai_provider.complete(prompt)
        rel, concept = self.notes.create(
            NoteInput(
                title=f"{source.title} (caption)",
                body=f"{caption}\n\nFor [{source.title}]({_rel_from(source_path)}).",
                type=KIND_CAPTION,
                tags=["generated"],
                origin=Origin.GENERATED,
                source=source_path,
                links=[source_path],
            )
        )
        self._link_back(source_path, rel)
        self.index.index_concept(rel, concept)
        return rel

    def _first_image_attachment(self, concept) -> bytes | None:
        """Return the bytes of the first image attachment on a note, if any."""
        for att in concept.vesnai.get("attachments", []) or []:
            if str(att).lower().endswith(_IMAGE_EXTS) and self.notes.store.exists(att):
                return self.notes.store.read_attachment(att)
        return None

    def _link_back(self, source_path: str, child_path: str) -> None:
        source = self.notes.get(source_path)
        links = source.vesnai.setdefault("links", [])
        if child_path not in links:
            links.append(child_path)
            self.notes.store.write_concept(source_path, source, message="link generated child")


def _stem(rel_path: str) -> str:
    name = rel_path.rsplit("/", 1)[-1]
    return name[:-3] if name.endswith(".md") else name


def _rel_from(target: str) -> str:
    # Notes live under notes/; targets are bundle-relative -> step up one level.
    return f"../{target}"
