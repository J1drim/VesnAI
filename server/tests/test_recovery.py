from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from vesnai.api.server import create_app
from vesnai.app_state import AppState
from vesnai.config import Settings
from vesnai.notes import NoteInput, NoteService
from vesnai.okf.bundle import BundleError, BundleStore
from vesnai.okf.model import Origin


def test_trash_restores_children_media_and_retains_shared_attachment(tmp_path):
    store = BundleStore(tmp_path)
    notes = NoteService(store)
    store.save_attachment('attachments/image.png', b'image')
    parent, _ = notes.create(NoteInput(title='Parent', attachments=['attachments/image.png']))
    child, _ = notes.create(NoteInput(title='Caption', type='GeneratedCaption',
                                     origin=Origin.GENERATED, source=parent))
    other, _ = notes.create(NoteInput(title='Shared', attachments=['attachments/image.png']))
    notes.delete(parent)
    assert not store.exists(parent) and not store.exists(child)
    assert store.exists(other) and store.exists('attachments/image.png')
    item = notes.recovery.list()[0]
    assert set(item['paths']) == {parent, child}
    assert set(notes.recovery.restore(item['id'])) == {parent, child}
    assert store.read_concept(parent).vesnai['version'] == 2
    assert store.read_attachment('attachments/image.png') == b'image'
    assert notes.recovery.list() == []


def test_trash_conflicts_preflight_and_partial_restore_retries(tmp_path):
    store = BundleStore(tmp_path)
    notes = NoteService(store)
    path, concept = notes.create(NoteInput(title='Keep'))
    notes.delete(path)
    item = notes.recovery.list()[0]
    store.write_concept(path, concept)
    with pytest.raises(BundleError, match='already exists'):
        notes.recovery.restore(item['id'])
    assert len(notes.recovery.list()) == 1
    store.delete_concept(path)
    original = store.write_concept
    def write_then_crash(*args, **kwargs):
        original(*args, **kwargs)
        raise OSError('interrupted')
    with patch.object(store, 'write_concept', write_then_crash), pytest.raises(OSError):
        notes.recovery.restore(item['id'])
    assert notes.recovery.restore(item['id']) == [path]
    assert store.read_concept(path).vesnai['version'] == 2


def test_revision_restore_is_new_edit_and_recovers_media(tmp_path):
    store = BundleStore(tmp_path)
    notes = NoteService(store)
    store.save_attachment('attachments/old.png', b'old')
    path, _ = notes.create(NoteInput(title='Before', body='![old](attachments/old.png)'))
    revision = notes.recovery.history(path)['revisions'][0]['revision']
    notes.update(path, body='new', title='After')
    store.delete_attachment('attachments/old.png')
    with pytest.raises(BundleError, match='changed'):
        notes.recovery.restore_revision(path, revision, 1)
    assert store.read_concept(path).title == 'After'
    notes.recovery.restore_revision(path, revision, 2)
    current = store.read_concept(path)
    assert current.title == 'Before' and current.vesnai['version'] == 3
    assert store.read_attachment('attachments/old.png') == b'old'
    assert len(notes.recovery.history(path)['revisions']) == 3
    with pytest.raises(ValueError):
        notes.recovery.revision(path, '--all')
    with pytest.raises(ValueError):
        notes.recovery.history('.git/config')


def test_other_paired_device_can_restore_trash_with_media(tmp_path):
    state = AppState(Settings(knowledge_dir=tmp_path / 'kb', data_dir=tmp_path / 'data',
                              advertise_mdns=False, offline_only=True, auto_illustrate=False))
    with TestClient(create_app(state)) as client:
        headers = []
        for name in ['phone', 'desktop']:
            token = state.auth.redeem_pairing_code(state.auth.create_pairing_code(), name)
            headers.append({'Authorization': f'Bearer {token}'})
        assert client.get('/v1/library/trash').status_code == 401
        state.store.save_attachment('attachments/file.bin', b'payload')
        path, note = state.notes.create(NoteInput(title='Cross device', attachments=['attachments/file.bin']))
        result = client.post('/v1/sync/push', headers=headers[0], json={
            'device': 'phone', 'changes': [{'path': path, 'deleted': True, 'base_version': note.vesnai['version']}]})
        assert result.status_code == 200
        assert not state.store.exists(path)
        item = client.get('/v1/library/trash', headers=headers[1]).json()['items'][0]
        response = client.post(f'/v1/library/trash/{item["id"]}/restore', headers=headers[1])
        assert response.status_code == 200
        assert state.store.read_attachment('attachments/file.bin') == b'payload'
        assert state.store.exists(path)
