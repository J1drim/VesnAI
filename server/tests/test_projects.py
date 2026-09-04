from unittest.mock import Mock

from fastapi.testclient import TestClient

from vesnai.api.server import create_app
from vesnai.app_state import AppState
from vesnai.config import Settings
from vesnai.notes import NoteInput
from vesnai.providers.base import ChatMessage


def test_project_answers_enforce_scope_and_do_not_offer_tools(tmp_path):
    state = AppState(Settings(knowledge_dir=tmp_path / 'kb', data_dir=tmp_path / 'data',
                              advertise_mdns=False, offline_only=True, auto_illustrate=False))
    with TestClient(create_app(state)) as client:
        assert client.post('/v1/library/ask', json={'question': 'plan?', 'paths': []}).status_code == 401
        token = state.auth.redeem_pairing_code(state.auth.create_pairing_code(), 'test')
        headers = {'Authorization': f'Bearer {token}'}
        included, _ = state.notes.create(NoteInput(title='Launch', body='Launch in May', tags=['project']))
        excluded, _ = state.notes.create(NoteInput(title='Private', body='Outside scope secret'))
        removed, _ = state.notes.create(NoteInput(title='Moved', body='Former project secret', tags=['other']))
        state.store.save_attachment('attachments/file.md', b'attachment, not a note')
        assert 'attachments/file.md' not in state.store.list_paths()
        req = {'question': 'When is launch?',
               'paths': [included, removed, 'memory/user.md', '.git/config', '/notes/foo.md'],
               'view': {'tag': 'project', 'scope': 'active'}}
        assert client.post('/v1/library/ask', json=req, headers=headers).json()['demo_mode']
        model = Mock()
        model.chat.return_value = ChatMessage(role='assistant', content='In May [1]. Unverified [99].')
        state.providers.ai = model
        response = client.post('/v1/library/ask', json=req, headers=headers)
        assert response.status_code == 200
        result = response.json()
        assert [source['path'] for source in result['sources']] == [included]
        assert result['scope_count'] == 1
        messages = model.chat.call_args.args[0]
        text = '\n'.join(message.content for message in messages)
        assert 'Outside scope secret' not in text and 'Former project secret' not in text
        assert model.chat.call_args.kwargs['tools'] == []
        assert state.store.read_concept(excluded).vesnai['version'] == 1
        model.chat.reset_mock()
        empty = client.post('/v1/library/ask', json={'question': 'plan?', 'paths': []}, headers=headers)
        assert empty.json()['scope_empty']
        model.chat.assert_not_called()
