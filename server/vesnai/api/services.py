"""Provider configuration versus explicitly probed availability."""
from datetime import UTC, datetime

from fastapi import APIRouter, Depends

from vesnai.api.deps import get_state, require_device
from vesnai.app_state import AppState
from vesnai.providers.base import ChatMessage
from vesnai.providers.fakes import (
    FakeAIProvider,
    FakeEmbeddingProvider,
    FakeImageProvider,
    FakeSearchProvider,
    FakeSTTProvider,
    FakeTTSProvider,
    FakeVisionProvider,
)

router = APIRouter(prefix='/v1/library', tags=['services'])
FAKES = (FakeAIProvider, FakeEmbeddingProvider, FakeImageProvider, FakeSearchProvider,
         FakeSTTProvider, FakeTTSProvider, FakeVisionProvider)


def configured_services(state: AppState) -> dict[str, str]:
    providers = {'chat': state.providers.ai, 'embeddings': state.providers.embedder,
                 'images': state.providers.image, 'vision': state.providers.vision,
                 'voice': state.providers.tts, 'critique': state.providers.marena}
    return {name: 'unavailable' if provider is None else 'demo' if isinstance(provider, FAKES)
            else 'configured_unchecked' for name, provider in providers.items()}


@router.post('/services/check')
def check_services(state: AppState = Depends(get_state), _=Depends(require_device)) -> dict:
    statuses = configured_services(state)
    if statuses['chat'] == 'configured_unchecked':
        try:
            result = state.providers.ai.chat([ChatMessage(role='user', content='Reply with OK only.')], tools=[])
            statuses['chat'] = 'available' if result.content.strip() else 'unavailable'
        except Exception:
            statuses['chat'] = 'unavailable'
    if statuses['embeddings'] == 'configured_unchecked':
        try:
            vectors = state.providers.embedder.embed(['VesnAI availability check'])
            statuses['embeddings'] = 'available' if len(vectors) == 1 and len(vectors[0]) else 'unavailable'
        except Exception:
            statuses['embeddings'] = 'unavailable'
    # Never generate an image, synthesize speech or run a critique as a health probe.
    return {'services': statuses, 'checked_at': datetime.now(UTC).isoformat()}
