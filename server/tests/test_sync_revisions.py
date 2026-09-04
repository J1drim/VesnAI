from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy

from vesnai.notes import NoteInput, NoteService
from vesnai.okf.bundle import BundleStore
from vesnai.okf.parse import dump_concept
from vesnai.sync import Change, SyncService


def env(tmp_path):
    store = BundleStore(tmp_path / 'kb', use_git=False)
    notes = NoteService(store)
    sync = SyncService(store, tmp_path / 'data', notes=notes)
    path, original = notes.create(NoteInput(title='Original', body='base'))
    return store, notes, sync, path, original


def test_two_devices_same_base_never_silently_overwrite(tmp_path):
    store, _, sync, path, original = env(tmp_path)
    def upload(body):
        edited = deepcopy(original)
        edited.body = body
        return sync.push([Change(path, doc=dump_concept(edited), base_version=1)])
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(upload, ['phone', 'desktop']))
    assert sum(bool(r.applied) for r in results) == 1
    conflicts = [c for r in results for c in r.conflicts]
    assert len(conflicts) == 1
    assert {store.read_concept(path).body, store.read_concept(conflicts[0]['kept']).body} == {'phone', 'desktop'}
    assert store.read_concept(path).vesnai['version'] == 2


def test_replayed_ack_is_idempotent_and_metadata_survives(tmp_path):
    store, _, sync, path, original = env(tmp_path)
    original.frontmatter['custom'] = {'nested': ['keep']}
    original.vesnai['extension'] = 'keep too'
    store.write_concept(path, original)
    incoming = deepcopy(original)
    incoming.body = 'edited'
    incoming.frontmatter.pop('custom')
    incoming.vesnai.pop('extension')
    incoming.vesnai['id'] = 'spoofed'
    incoming.vesnai['version'] = 100
    change = Change(path, doc=dump_concept(incoming), base_version=1)
    first = sync.push([change])
    second = sync.push([change])
    assert first.versions == second.versions == {path: 2}
    assert first.cursor == second.cursor
    assert not second.conflicts
    saved = store.read_concept(path)
    assert saved.frontmatter['custom'] == {'nested': ['keep']}
    assert saved.vesnai['extension'] == 'keep too'
    assert saved.vesnai['id'] == original.vesnai['id']
    assert saved.vesnai['created'] == original.vesnai['created']


def test_delete_edit_races_require_resolution(tmp_path):
    store, notes, sync, path, original = env(tmp_path)
    notes.update(path, body='server changed')
    result = sync.push([Change(path, deleted=True, base_version=1)])
    assert not result.applied and result.conflicts[0]['server_version'] == 2
    assert store.exists(path)
    sync.push([Change(path, deleted=True, base_version=2)])
    original.body = 'late offline edit'
    result = sync.push([Change(path, doc=dump_concept(original), base_version=1)])
    assert not result.applied and result.conflicts[0]['server_version'] == 0
    assert not store.exists(path)


def test_partial_batch_and_unique_conflict_copies(tmp_path):
    store, notes, sync, path, original = env(tmp_path)
    notes.update(path, body='server changed')
    original.body = 'local change'
    conflict = Change(path, doc=dump_concept(original), base_version=1)
    first = sync.push([Change('notes/bad.md', doc='bad'), conflict])
    second = sync.push([conflict])
    assert len(first.conflicts) == 2
    assert first.conflicts[1]['kept'] != second.conflicts[0]['kept']
    assert store.read_concept(first.conflicts[1]['kept']).vesnai['id'] != original.vesnai['id']
