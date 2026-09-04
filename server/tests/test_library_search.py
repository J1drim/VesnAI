from unittest.mock import Mock

from fastapi.testclient import TestClient

from vesnai.ai.vectorstore import VectorHit
from vesnai.api.server import create_app
from vesnai.app_state import AppState
from vesnai.config import Settings
from vesnai.notes import NoteInput


def test_library_search_auth_demo_and_scope(tmp_path):
    state = AppState(Settings(knowledge_dir=tmp_path / 'kb', data_dir=tmp_path / 'data',
                              advertise_mdns=False, offline_only=True, auto_illustrate=False))
    with TestClient(create_app(state)) as client:
        assert client.post('/v1/library/search', json={'query': 'hello'}).status_code == 401
        token = state.auth.redeem_pairing_code(state.auth.create_pairing_code(), 'test')
        headers = {'Authorization': f'Bearer {token}'}
        demo = client.post('/v1/library/search', json={'query': 'hello'}, headers=headers)
        assert demo.json() == {'available': False, 'demo_mode': True, 'results': []}
        first, _ = state.notes.create(NoteInput(title='One', body='creative work'))
        second, _ = state.notes.create(NoteInput(title='Two', body='creative work'))
        state.index.embedder = Mock()
        state.index.search = Mock(return_value=[VectorHit(id=first, score=.9), VectorHit(id=second, score=.8)])
        response = client.post('/v1/library/search', json={'query': 'creative', 'paths': [second]}, headers=headers)
        assert response.status_code == 200
        result = response.json()
        assert result['available'] and not result['demo_mode']
        assert [r['note']['path'] for r in result['results']] == [second]
        assert result['results'][0]['reason'] == 'semantic_similarity'
        assert state.store.read_concept(second).vesnai['version'] == 1  # suggestions never write
        empty = client.post('/v1/library/search', json={'query': 'creative', 'paths': []}, headers=headers)
        assert empty.json()['results'] == []
        assert client.post('/v1/library/search', json={'query': '', 'limit': 999}, headers=headers).status_code == 422
