from unittest.mock import Mock

from fastapi.testclient import TestClient

from vesnai.api.server import create_app
from vesnai.app_state import AppState
from vesnai.config import Settings
from vesnai.providers.base import ChatMessage


def test_status_separates_demo_configuration_and_explicit_checks(tmp_path):
    state = AppState(Settings(knowledge_dir=tmp_path / 'kb', data_dir=tmp_path / 'data',
                              advertise_mdns=False, offline_only=True, auto_illustrate=False,
                              marena_enabled=False))
    with TestClient(create_app(state)) as client:
        assert client.post('/v1/library/services/check').status_code == 401
        token = state.auth.redeem_pairing_code(state.auth.create_pairing_code(), 'phone')
        headers = {'Authorization': f'Bearer {token}'}
        settings = client.get('/v1/settings', headers=headers).json()
        assert not settings['auto_illustrate'] and not settings['marena_enabled']
        assert settings['service_status']['chat'] == 'demo'
        state.providers.ai = Mock()
        state.providers.ai.chat.return_value = ChatMessage(role='assistant', content='OK')
        state.providers.embedder = Mock()
        state.providers.embedder.embed.side_effect = OSError('unreachable')
        state.providers.image = Mock()
        settings = client.get('/v1/settings', headers=headers).json()
        assert settings['service_status']['chat'] == 'configured_unchecked'
        state.providers.ai.chat.assert_not_called()
        status = client.post('/v1/library/services/check', headers=headers).json()['services']
        assert status['chat'] == 'available' and status['embeddings'] == 'unavailable'
        assert status['images'] == 'configured_unchecked'
        state.providers.image.generate.assert_not_called()


def test_ack_endpoint_only_acknowledges_authenticated_device(tmp_path):
    state = AppState(Settings(knowledge_dir=tmp_path / 'kb', data_dir=tmp_path / 'data',
                              advertise_mdns=False, offline_only=True, auto_illustrate=False))
    with TestClient(create_app(state)) as client:
        headers = []
        for name in ['phone', 'desktop']:
            token = state.auth.redeem_pairing_code(state.auth.create_pairing_code(), name)
            headers.append({'Authorization': f'Bearer {token}'})
        event = state.notifications.append(kind='image_ready', title='Complete')
        assert client.post('/v1/notifications/ack', headers=headers[0], json={'ids': [event.id]}).json()['acked'] == 1
        assert client.get('/v1/notifications', headers=headers[0]).json() == []
        assert client.get('/v1/notifications', headers=headers[1]).json()[0]['id'] == event.id
