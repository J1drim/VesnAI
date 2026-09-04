"""Explicit library discovery, separate from assistant/web research."""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from vesnai.api.deps import get_state, require_device
from vesnai.api.routes import _to_out
from vesnai.app_state import AppState
from vesnai.providers.fakes import FakeEmbeddingProvider

router = APIRouter(prefix='/v1/library', tags=['library'])


class LibrarySearch(BaseModel):
    query: str = Field(min_length=1, max_length=6000)
    limit: int = Field(default=12, ge=1, le=50)
    exclude_path: str = ''
    paths: list[str] | None = Field(default=None, max_length=10000)
    include_archived: bool = False


@router.post('/search')
def search_library(req: LibrarySearch, state: AppState = Depends(get_state), _=Depends(require_device)) -> dict:
    if isinstance(state.index.embedder, FakeEmbeddingProvider):
        return {'available': False, 'demo_mode': True, 'results': []}
    scope = None if req.paths is None else set(req.paths)
    try:
        hits = state.index.search(req.query, top_k=max(req.limit * 4, 50), strict=True, paths=scope)
    except Exception as exc:
        raise HTTPException(status_code=503, detail='Embedding service unavailable') from exc
    results = []
    with state.store.lock:
        for hit in hits:
            path = hit.id
            if path == req.exclude_path or (scope is not None and path not in scope):
                continue
            if '.conflict-' in path or not state.store.exists(path):
                continue
            note = state.store.read_concept(path)
            if note.type == 'ChatTranscript' or (note.vesnai.get('archived') and not req.include_archived):
                continue
            results.append({'note': _to_out(path, note).model_dump(), 'score': hit.score,
                            'reason': 'semantic_similarity', 'preview': hit.payload.get('text_preview', '')})
            if len(results) >= req.limit:
                break
    return {'available': True, 'demo_mode': False, 'results': results}
