"""Recoverable deletion snapshots and read-only, path-scoped Git history."""
from __future__ import annotations

import builtins
import json
import os
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path

from vesnai.attachment_refs import attachment_refs_from_concept
from vesnai.ids import uuid7
from vesnai.okf.bundle import BundleError, BundleStore, bundle_locked
from vesnai.okf.parse import dump_concept, parse_concept
from vesnai.security import assert_sync_path_allowed


class RecoveryService:
    def __init__(self, store: BundleStore):
        self.store = store
        self.root = store.root / '.recovery'

    def _item(self, item_id: str) -> Path:
        if not re.fullmatch(r'[a-f0-9-]{32,36}', item_id):
            raise ValueError('Invalid trash item')
        return self.root / f'{item_id}.zip'

    @bundle_locked
    def snapshot(self, paths: list[str], primary: str) -> str:
        concepts = {p: self.store.read_concept(p) for p in paths if self.store.exists(p)}
        if primary not in concepts:
            return ''
        item_id = uuid7()
        self.root.mkdir(exist_ok=True)
        metadata = {'id': item_id, 'path': primary, 'title': concepts[primary].title,
                    'deleted_at': self.store.clock.now().isoformat(), 'paths': list(concepts)}
        fd, temp = tempfile.mkstemp(dir=self.root, suffix='.tmp')
        try:
            with os.fdopen(fd, 'wb') as output:
                with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
                    archive.writestr('metadata.json', json.dumps(metadata))
                    for path, concept in concepts.items():
                        archive.writestr(f'notes/{path}', dump_concept(concept))
                    media = set().union(*(attachment_refs_from_concept(c) for c in concepts.values()))
                    for path in sorted(media):
                        if path.startswith('attachments/') and self.store.exists(path):
                            archive.writestr(f'media/{path}', self.store.read_attachment(path))
                output.flush()
                os.fsync(output.fileno())
            os.replace(temp, self._item(item_id))
        finally:
            Path(temp).unlink(missing_ok=True)
        return item_id

    @bundle_locked
    def list(self) -> list[dict]:
        items = []
        for path in self.root.glob('*.zip'):
            with zipfile.ZipFile(path) as archive:
                items.append(json.loads(archive.read('metadata.json')))
        return sorted(items, key=lambda i: i['deleted_at'], reverse=True)

    @bundle_locked
    def restore(self, item_id: str) -> builtins.list[str]:
        target = self._item(item_id)
        with zipfile.ZipFile(target) as archive:
            metadata = json.loads(archive.read('metadata.json'))
            concepts = {}
            for path in metadata['paths']:
                assert_sync_path_allowed(path)
                self.store._resolve(path)
                concept = parse_concept(archive.read(f'notes/{path}').decode('utf-8'))
                if self.store.exists(path):
                    existing = self.store.read_concept(path)
                    if existing.vesnai.get('restored_from_trash') == item_id:
                        continue  # safe replay after a partially completed restore
                    raise BundleError(f'A note already exists at {path}; nothing was replaced')
                concepts[path] = concept
            media = {}
            for name in archive.namelist():
                if not name.startswith('media/attachments/'):
                    continue
                path = name.removeprefix('media/')
                self.store._resolve(path)
                data = archive.read(name)
                if self.store.exists(path) and self.store.read_attachment(path) != data:
                    raise BundleError(f'Attachment content changed at {path}; nothing was replaced')
                media[path] = data
        # Preflight the complete snapshot before any writes. Keep it until all
        # writes succeed so crashes can retry; note identity makes replay safe.
        for path, data in media.items():
            if not self.store.exists(path):
                self.store.save_attachment(path, data)
        for path, concept in concepts.items():
            concept.vesnai['version'] = int(concept.vesnai.get('version', 1)) + 1
            concept.vesnai['updated'] = self.store.clock.now().isoformat()
            concept.vesnai['restored_from_trash'] = item_id
            vector = concept.vesnai.setdefault('version_vector', {})
            vector['server'] = int(vector.get('server', 0)) + 1
            self.store.write_concept(path, concept, message=f'restore from trash {path}')
        target.unlink()
        self.store._commit(f'complete trash restore {item_id}')
        return metadata['paths']

    @bundle_locked
    def discard(self, item_id: str) -> None:
        self._item(item_id).unlink()
        self.store._commit(f'discard trash snapshot {item_id}')

    @bundle_locked
    def history(self, path: str) -> dict:
        assert_sync_path_allowed(path)
        self.store._resolve(path)
        if not self.store.use_git:
            return {'available': False, 'revisions': []}
        result = self.store._git('log', '-50', '--format=%H%x09%cI%x09%s', '--', path)
        revisions = []
        for line in result.stdout.splitlines():
            revision, date, title = line.split('\t', 2)
            revisions.append({'revision': revision, 'date': date, 'title': title})
        return {'available': True, 'revisions': revisions}

    @bundle_locked
    def revision(self, path: str, revision: str) -> str:
        assert_sync_path_allowed(path)
        self.store._resolve(path)
        if not re.fullmatch(r'[a-f0-9]{40}', revision):
            raise ValueError('Invalid revision')
        result = self.store._git('show', f'{revision}:{path}')
        if result.returncode:
            raise BundleError('This revision does not contain the note')
        return result.stdout

    @bundle_locked
    def restore_revision(self, path: str, revision: str, base_version: int) -> None:
        old = parse_concept(self.revision(path, revision))
        current = self.store.read_concept(path)
        if int(current.vesnai.get('version', 1)) != base_version:
            raise BundleError('The note changed; sync and review the revision again')
        media = {}
        for attachment in attachment_refs_from_concept(old):
            if not attachment.startswith('attachments/'):
                continue
            self.store._resolve(attachment)
            result = subprocess.run(['git', '-C', str(self.store.root), 'show', f'{revision}:{attachment}'],
                                    capture_output=True, check=False)
            if result.returncode:
                if not self.store.exists(attachment):
                    raise BundleError(f'Revision attachment is unavailable: {attachment}')
                continue
            if self.store.exists(attachment) and self.store.read_attachment(attachment) != result.stdout:
                raise BundleError(f'Attachment changed: {attachment}; nothing was replaced')
            media[attachment] = result.stdout
        for attachment, data in media.items():
            if not self.store.exists(attachment):
                self.store.save_attachment(attachment, data)
        # Historical content is a new edit, never a Git reset or identity rollback.
        for key in ('id', 'created', 'profile_version', 'version_vector'):
            if key in current.vesnai:
                old.vesnai[key] = current.vesnai[key]
        old.vesnai['version'] = base_version + 1
        old.vesnai['updated'] = self.store.clock.now().isoformat()
        vector = old.vesnai.setdefault('version_vector', {})
        vector['server'] = int(vector.get('server', 0)) + 1
        self.store.write_concept(path, old, message=f'restore revision {revision[:12]} of {path}')
