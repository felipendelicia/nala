from contextlib import closing
import hashlib
import http.client
import io
import json
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from unittest.mock import patch

from nala_server.protocol import MAX_JSON
from nala_server.storage import SCHEMA, Store

SERVER = Path(__file__).resolve().parent
CHUNK = 4 * 1024 * 1024
DATE = '2026-11-24T12:00:00.000Z'


def revision(revision_id, *, title='Álgebra', book_fields=None, page_fields=None):
    return {
        'schemaVersion': 1, 'id': revision_id, 'deviceId': 'tablet',
        'parentId': None, 'createdAt': DATE,
        'notebook': {
            'schemaVersion': 1, 'id': 'diario', 'title': title,
            'subject': 'Matemática', 'updatedAt': DATE,
            'pages': [{
                'id': 'página', 'width': 200, 'height': 300,
                'background': {'kind': 'paper', 'pattern': 'blank'}, 'strokes': [],
                **(page_fields or {}),
            }],
            **(book_fields or {}),
        },
    }


class RevisionPageTest(unittest.TestCase):
    def test_page_budget_preserves_order_and_allows_a_large_revision(self):
        payloads = [b'a' * 12, b'b' * 17, b'c' * 25, b'd' * 52, b'e' * 6]
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.executescript(SCHEMA)
        db.executemany('INSERT INTO revisions (id, payload) VALUES (?, ?)',
                       [(str(index), payload) for index, payload in enumerate(payloads)])
        store = Store(Path('.'))

        with patch('nala_server.storage.REVISION_PAGE_BUDGET', 30):
            after = 0
            for expected, size, cursor, more in [
                (payloads[:2], 30, 2, True),
                (payloads[2:3], 25, 3, True),
                (payloads[3:4], 52, 4, True),
                (payloads[4:], 6, 5, False),
                ([], 0, 5, False),
            ]:
                rows, actual_size, next_cursor, has_more = store.revision_page(db, after, 50)
                self.assertEqual([row[0] for row in rows], expected)
                self.assertEqual((actual_size, next_cursor, has_more), (size, cursor, more))
                after = cursor


class ServerTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.scratch = Path(directory.name)
        self.data = self.scratch / 'data'
        with socket.socket() as reserved:
            reserved.bind(('127.0.0.1', 0))
            self.port = reserved.getsockname()[1]
        self.env = {
            **os.environ, 'NALA_BIND': '127.0.0.1', 'NALA_PORT': str(self.port),
            'NALA_DATA_DIR': str(self.data), 'PYTHONDONTWRITEBYTECODE': '1',
        }
        self.addCleanup(self.stop)
        self.process = None
        self.token = self.command('token-create', 'tablet').stdout.strip()
        self.start()
        self.identity = self.identify()

    def command(self, *args, check=True, data=None):
        env = self.env if data is None else {**self.env, 'NALA_DATA_DIR': str(data)}
        result = subprocess.run(
            [sys.executable, '-m', 'nala_server', *args],
            cwd=SERVER, env=env, capture_output=True, text=True, timeout=10,
        )
        if check:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def start(self):
        with (self.scratch / 'server.log').open('wb') as log:
            self.process = subprocess.Popen(
                [sys.executable, '-m', 'nala_server', 'serve'],
                cwd=SERVER, env=self.env, stdout=log, stderr=log,
            )
        for _ in range(100):
            try:
                with socket.create_connection(('127.0.0.1', self.port), 0.1):
                    return
            except OSError:
                if self.process.poll() is not None:
                    break
                time.sleep(0.02)
        self.fail((self.scratch / 'server.log').read_text())

    def stop(self):
        if self.process is not None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
            self.process = None

    def request(self, method, path, *, body=None, headers=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        request_headers = {'Authorization': 'Bearer ' + self.token, **(headers or {})}
        if path != '/identity':
            request_headers.setdefault('X-Nala-Server', self.identity)
        if isinstance(body, dict):
            body = json.dumps(body).encode()
            request_headers.setdefault('Content-Type', 'application/json')
        request_headers = {key: value for key, value in request_headers.items() if value is not None}
        try:
            connection.request(method, '/v1' + path, body, request_headers)
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def read_json(self, path):
        status, _, body = self.request('GET', path)
        self.assertEqual(status, 200, body)
        return json.loads(body)

    def identify(self):
        return self.read_json('/identity')['id']

    def patch(self, path, start, total, data):
        return self.request('PATCH', path, body=data, headers={
            'Upload-Offset': str(start), 'Upload-Length': str(total),
        })

    def test_bearer_authentication_revocation_and_distinct_credentials(self):
        status, headers, body = self.request('GET', '/identity', headers={'Authorization': None})
        self.assertEqual(status, 401)
        self.assertEqual(headers['WWW-Authenticate'], 'Bearer')
        self.assertNotIn(self.token.encode(), body)
        other_token = self.command('token-create', 'pc').stdout.strip()
        self.assertNotEqual(self.token, other_token)
        self.assertNotEqual(self.command('token-create', 'pc', check=False).returncode, 0)
        self.command('token-revoke', 'tablet')
        self.assertEqual(self.request('GET', '/identity')[0], 401)
        self.assertEqual(self.request('GET', '/folders')[0], 401)
        self.token = other_token
        self.assertEqual(self.identify(), self.identity)

    def test_identity_guard_runs_before_processing_any_data_route(self):
        routes = [
            ('GET', '/revisions'), ('PUT', '/revisions'),
            ('GET', '/folders'), ('PUT', '/folders'),
            ('GET', '/assets/' + '0' * 64), ('HEAD', '/assets/' + '0' * 64),
            ('PATCH', '/assets/' + '0' * 64),
        ]
        for method, route in routes:
            for identity in [None, 'old-generation']:
                with self.subTest(method=method, route=route, identity=identity):
                    status, headers, body = self.request(
                        method, route, headers={'X-Nala-Server': identity},
                    )
                    self.assertEqual(status, 409)
                    self.assertNotIn('Upload-Offset', headers)
                    if method != 'HEAD':
                        self.assertEqual(json.loads(body), {'error': 'server_changed'})
        self.assertEqual(self.read_json('/revisions')['items'], [])

    def test_immutable_idempotent_revisions_and_cursor_pagination(self):
        first = revision('uno')
        self.assertEqual(self.request('PUT', '/revisions', body=first)[0], 204)
        reencoded = dict(reversed(list(first.items())))
        self.assertEqual(self.request('PUT', '/revisions', body=reencoded)[0], 204)
        self.assertEqual(self.request('PUT', '/revisions', body=revision('uno', title='Cambio'))[0], 409)
        second = revision('dos')
        self.assertEqual(self.request('PUT', '/revisions', body=second)[0], 204)
        page = self.read_json('/revisions?after=0&limit=1')
        self.assertEqual(page, {'items': [first], 'next': 1, 'more': True})
        page = self.read_json('/revisions?after=1&limit=3')
        self.assertEqual(page, {'items': [second], 'next': 2, 'more': False})
        self.assertEqual(self.read_json('/revisions?after=2'), {'items': [], 'next': 2, 'more': False})
        self.assertEqual(self.request('GET', '/revisions?after=-1')[0], 400)

    def test_sync_failure_log_omits_credentials_and_note_content(self):
        record = revision('private-revision-id', title='Private title')
        self.assertEqual(self.request('PUT', '/revisions', body=record)[0], 204)
        different = {**record, 'notebook': {**record['notebook'], 'title': 'Private update'}}
        self.assertEqual(self.request('PUT', '/revisions', body=different)[0], 409)
        status, _, _ = self.request('PUT', '/revisions', headers={
            'Content-Length': str(MAX_JSON + 1),
        })
        self.assertEqual(status, 413)

        log = (self.scratch / 'server.log').read_text()
        self.assertIn('PUT revisions: status=409 reason=revision_conflict', log)
        self.assertIn('PUT revisions: status=413 reason=request_too_large', log)
        for secret in (self.token, self.identity, 'private-revision-id', 'Private title', 'Private update'):
            self.assertNotIn(secret, log)

    def test_revision_requires_all_published_attachment_types(self):
        image = {'id': 'imagen', 'kind': 'image', 'x': 0, 'y': 0, 'width': 10, 'height': 10}
        preview = hashlib.sha256(b'preview').hexdigest()
        self.assertEqual(self.patch('/assets/' + preview, 0, 7, b'preview')[0], 204)
        fields = [
            ('cover', 'book', {'coverAssetId': '%s'}),
            ('recording', 'book', {'recordings': [{
                'id': 'audio', 'title': 'Clase', 'createdAt': DATE,
                'durationMs': 100, 'assetId': '%s',
            }]}),
            ('background', 'page', {'background': {'kind': 'pdf', 'assetId': '%s', 'pageNumber': 1}}),
            ('voice', 'page', {'comments': [{
                'id': 'nota', 'x': 10, 'y': 10, 'text': '', 'createdAt': DATE,
                'audioDurationMs': 100, 'audioAssetId': '%s',
            }]}),
            ('edited', 'page', {'objects': [{**image, 'assetId': '%s'}]}),
            ('original', 'page', {'objects': [{**image, 'assetId': preview, 'originalAssetId': '%s'}]}),
        ]
        for name, level, field in fields:
            with self.subTest(name=name):
                data = name.encode()
                asset = hashlib.sha256(data).hexdigest()
                content = json.loads(json.dumps(field) % asset)
                kwargs = {f'{level}_fields': content}
                book = revision(name, **kwargs)
                self.assertEqual(self.request('PUT', '/revisions', body=book)[0], 409)
                self.assertEqual(self.patch('/assets/' + asset, 0, len(data), data)[0], 204)
                self.assertEqual(self.request('PUT', '/revisions', body=book)[0], 204)

    def test_upload_resumes_after_restart_and_supports_ranged_downloads(self):
        data = b'N' * CHUNK + b'last bytes'
        total = len(data)
        path = '/assets/' + hashlib.sha256(data).hexdigest()
        status, _, _ = self.request('PATCH', path, headers={
            'Content-Length': str(total), 'Upload-Offset': '0', 'Upload-Length': str(total),
        })
        self.assertEqual(status, 413)
        status, headers, _ = self.patch(path, 0, total, data[:CHUNK])
        self.assertEqual((status, headers['Upload-Offset']), (204, str(CHUNK)))
        self.assertEqual(self.request('GET', path)[0], 404)
        self.stop()
        self.start()
        self.assertEqual(self.identify(), self.identity)
        status, headers, _ = self.request('HEAD', path)
        self.assertEqual((status, headers['Upload-Offset']), (404, str(CHUNK)))
        status, headers, _ = self.patch(path, 0, total, data[:CHUNK])
        self.assertEqual((status, headers['Upload-Offset']), (409, str(CHUNK)))
        status, headers, _ = self.patch(path, CHUNK, total, data[CHUNK:])
        self.assertEqual((status, headers['Upload-Offset']), (204, str(total)))
        status, headers, _ = self.request('HEAD', path)
        self.assertEqual((status, headers['Upload-Offset']), (200, str(total)))
        status, headers, body = self.request('GET', path, headers={'Range': f'bytes={CHUNK}-'})
        self.assertEqual((status, headers['Content-Range'], body),
                         (206, f'bytes {CHUNK}-{total - 1}/{total}', b'last bytes'))
        status, headers, _ = self.request('GET', path, headers={'Range': f'bytes={total}-'})
        self.assertEqual((status, headers['Content-Range']), (416, f'bytes */{total}'))
        self.assertEqual(self.request('GET', path)[2], data)

    def test_a_registered_missing_or_truncated_asset_can_be_repaired(self):
        for problem in ('missing', 'truncated'):
            with self.subTest(problem=problem):
                data = f'original bytes for {problem}'.encode()
                identifier = hashlib.sha256(data).hexdigest()
                path = '/assets/' + identifier
                stored = self.data / 'library' / 'assets' / identifier
                book = revision(problem, book_fields={'coverAssetId': identifier})
                self.assertEqual(self.patch(path, 0, len(data), data)[0], 204)
                self.assertEqual(self.request('PUT', '/revisions', body=book)[0], 204)
                if problem == 'missing':
                    stored.unlink()
                else:
                    stored.write_bytes(data[:1])

                status, headers, _ = self.request('HEAD', path)
                self.assertEqual((status, headers['Upload-Offset']), (404, '0'))
                self.assertEqual(self.request('GET', path)[0], 404)
                next_book = {**book, 'id': problem + '-next', 'parentId': problem}
                self.assertEqual(self.request('PUT', '/revisions', body=next_book)[0], 409)
                self.assertIn(book, self.read_json('/revisions')['items'])
                with closing(sqlite3.connect(self.data / 'library' / 'nala.sqlite3')) as db:
                    self.assertEqual(db.execute('SELECT size FROM assets WHERE id=?',
                                                (identifier,)).fetchone(), (len(data),))

                invalid = b'?' * len(data)
                self.assertEqual(self.patch(path, 0, len(data), invalid)[0], 400)
                self.assertEqual(self.request('GET', path)[0], 404)
                if problem == 'truncated':
                    self.assertEqual(stored.read_bytes(), data[:1])

                self.assertEqual(self.patch(path, 0, len(data), data[:4])[0], 204)
                self.stop()
                self.start()
                status, headers, _ = self.request('HEAD', path)
                self.assertEqual((status, headers['Upload-Offset']), (404, '4'))
                self.assertEqual(self.patch(path, 4, len(data), data[4:])[0], 204)
                self.assertEqual(self.request('GET', path)[2], data)
                self.assertEqual(self.request('HEAD', path)[0], 200)
                self.assertEqual(self.request('PUT', '/revisions', body=next_book)[0], 204)

    def test_hash_mismatch_never_publishes_and_allows_retry(self):
        path = '/assets/' + hashlib.sha256(b'correct').hexdigest()
        self.assertEqual(self.patch(path, 0, 7, b'corrupt')[0], 400)
        status, headers, _ = self.request('HEAD', path)
        self.assertEqual((status, headers['Upload-Offset']), (404, '0'))
        self.assertEqual(self.patch(path, 0, 7, b'correct')[0], 204)
        empty_path = '/assets/' + hashlib.sha256(b'').hexdigest()
        self.assertEqual(self.patch(empty_path, 0, 0, b'')[0], 204)
        self.assertEqual(self.request('GET', empty_path)[2], b'')

    def test_zero_offset_can_restart_staging_with_the_correct_length(self):
        path = '/assets/' + hashlib.sha256(b'correct').hexdigest()
        self.assertEqual(self.patch(path, 0, 10, b'bad')[0], 204)
        status, headers, _ = self.request('HEAD', path)
        self.assertEqual((status, headers.get('Upload-Length'), headers['Upload-Offset']),
                         (404, '10', '3'))
        self.assertEqual(self.patch(path, 0, 10, b'bad')[0], 409)
        self.assertEqual(self.patch(path, 3, 7, b'rect')[0], 400)
        self.assertEqual(self.patch(path, 0, 7, b'correct')[0], 204)
        self.assertEqual(self.request('GET', path)[2], b'correct')

    def test_head_recovers_an_interrupted_final_publication(self):
        for renamed in [False, True]:
            with self.subTest(renamed=renamed):
                data = b'renamed' if renamed else b'staged'
                digest = hashlib.sha256(data).hexdigest()
                route = '/assets/' + digest
                self.assertEqual(self.patch(route, 0, len(data), data[:3])[0], 204)
                self.stop()
                stage = self.data / 'library' / 'uploads' / digest
                with stage.open('ab') as file:
                    file.write(data[3:])
                if renamed:
                    stage.rename(self.data / 'library' / 'assets' / digest)
                self.start()
                status, headers, _ = self.request('HEAD', route)
                self.assertEqual((status, headers['Upload-Offset']), (200, str(len(data))))
                self.assertEqual(self.request('GET', route)[2], data)

    def test_folder_merge_preserves_tombstones_and_resolves_cycles(self):
        def folder(identifier, name, parent=None, updated=DATE, deleted=False):
            return {
                'id': identifier, 'name': name, 'parentId': parent,
                'updatedAt': updated, 'deleted': deleted,
            }

        def upload(*folders):
            for item in folders:
                self.assertEqual(self.request('PUT', '/folders', body=item)[0], 204)

        def catalog():
            return {item['id']: item for item in self.read_json('/folders')['items']}

        upload(folder('z', 'Z', 'a'), folder('a', 'A'))
        self.assertEqual(catalog()['z']['parentId'], 'a')
        update = '2026-11-25T12:00:00.000Z'
        upload(folder('a', 'A última', 'z', updated=update), folder('a', 'A antigua'))
        self.assertEqual(catalog()['a'], folder('a', 'A última', updated=update))
        self.assertEqual(catalog()['z']['parentId'], 'a')
        upload(folder('a', 'Árbol', updated=update, deleted=True))
        self.assertEqual(catalog()['a'], folder('a', 'Árbol', updated=update, deleted=True))
        self.assertIsNone(catalog()['z']['parentId'])

    def test_online_backup_restores_revision_assets_and_rotates_identity(self):
        asset = b'attachment'
        digest = hashlib.sha256(asset).hexdigest()
        item = revision('saved', book_fields={'coverAssetId': digest})
        self.assertEqual(self.patch('/assets/' + digest, 0, len(asset), asset)[0], 204)
        self.assertEqual(self.request('PUT', '/revisions', body=item)[0], 204)
        archive = self.scratch / 'backup.tar.gz'
        other_token = self.command('token-create', 'temporary').stdout.strip()
        self.command('backup', str(archive))
        self.command('token-revoke', 'tablet')
        self.assertNotEqual(self.command('restore', str(archive), check=False).returncode, 0)
        self.stop()
        self.assertNotEqual(self.command('restore', str(archive), check=False).returncode, 0)
        self.data = self.scratch / 'restored'
        self.env['NALA_DATA_DIR'] = str(self.data)
        self.command('restore', str(archive))
        self.start()
        self.assertEqual(self.request('GET', '/identity')[0], 401)
        self.token = other_token
        self.assertEqual(self.request('GET', '/identity')[0], 401)
        self.token = self.command('token-create', 'tablet').stdout.strip()
        self.assertNotEqual(self.identify(), self.identity)
        self.assertEqual(self.request('GET', '/revisions')[0], 409)
        self.identity = self.identify()
        self.assertEqual(self.read_json('/revisions')['items'], [item])
        self.assertEqual(self.request('GET', '/assets/' + digest)[2], asset)

    def test_folder_batch_validates_all_records_before_committing_any(self):
        parent = {'id': 'parent', 'name': 'Padre', 'updatedAt': DATE}
        child = {'id': 'child', 'name': 'Hija', 'parentId': 'parent', 'updatedAt': DATE}
        invalid = {**child, 'parentId': 'child'}
        self.assertEqual(self.request('PUT', '/folders', body={'items': [parent, invalid]})[0], 400)
        self.assertEqual(self.read_json('/folders')['items'], [])
        self.assertEqual(self.request('PUT', '/folders', body={'items': [child, parent]})[0], 204)
        folders = {item['id']: item for item in self.read_json('/folders')['items']}
        self.assertEqual(folders['child']['parentId'], 'parent')

    def test_failed_restore_rejects_unsafe_archive_and_leaves_target_empty(self):
        archive = self.scratch / 'unsafe.tar.gz'
        with tarfile.open(archive, 'w:gz') as output:
            entry = tarfile.TarInfo('../escape')
            entry.size = 4
            output.addfile(entry, io.BytesIO(b'data'))
        target = self.scratch / 'target'
        self.assertNotEqual(self.command('restore', str(archive), check=False, data=target).returncode, 0)
        self.assertFalse((self.scratch / 'escape').exists())
        valid = self.scratch / 'valid.tar.gz'
        self.command('backup', str(valid))
        self.command('restore', str(valid), data=target)

    def test_restore_can_retry_after_an_interrupted_extraction(self):
        archive = self.scratch / 'valid.tar.gz'
        self.command('backup', str(archive))
        target = self.scratch / 'target'
        pending = target / '.restore-pending'
        pending.mkdir(parents=True)
        (pending / '.nala-restore').touch()
        (pending / 'nala.sqlite3').write_bytes(b'interrupted file')
        self.assertNotEqual(self.command('token-create', 'other', check=False, data=target).returncode, 0)
        self.command('restore', str(archive), data=target)
        self.assertTrue((target / 'library' / 'nala.sqlite3').is_file())
        self.assertFalse(pending.exists())

    def test_restore_rejects_a_backup_with_a_corrupt_gzip_trailer(self):
        backup = self.scratch / 'backup.tar.gz'
        self.command('backup', str(backup))
        damaged = bytearray(backup.read_bytes())
        damaged[-8] ^= 0xff
        backup.write_bytes(damaged)
        target = self.scratch / 'target'
        self.assertNotEqual(self.command('restore', str(backup), check=False, data=target).returncode, 0)
        self.assertFalse((target / 'library').exists())

    def test_backup_preserves_the_previous_archive_if_an_asset_is_damaged(self):
        data = b'intact'
        digest = hashlib.sha256(data).hexdigest()
        self.assertEqual(self.patch('/assets/' + digest, 0, len(data), data)[0], 204)
        backup = self.scratch / 'backup.tar.gz'
        self.command('backup', str(backup))
        previous = backup.read_bytes()
        (self.data / 'library' / 'assets' / digest).write_bytes(b'broken')
        self.assertNotEqual(self.command('backup', str(backup), check=False).returncode, 0)
        self.assertEqual(backup.read_bytes(), previous)


if __name__ == '__main__':
    unittest.main()
