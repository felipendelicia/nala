from contextlib import closing, contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import secrets
import sqlite3
import stat
from threading import Lock

from .protocol import RequestError, folder_order, json_bytes, repair_folders

LIBRARY = 'library'
DATABASE = 'nala.sqlite3'
ASSETS = 'assets'
UPLOADS = 'uploads'
RESTORE_PENDING = '.restore-pending'
LOCKS = {'.operation.lock', '.serve.lock'}
REVISION_PAGE_BUDGET = 12 * 1024 * 1024

SCHEMA = """
CREATE TABLE IF NOT EXISTS metadata (
    key TEXT PRIMARY KEY, value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tokens (
    label TEXT PRIMARY KEY, digest BLOB NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS revisions (
    seq INTEGER PRIMARY KEY, id TEXT NOT NULL UNIQUE, payload BLOB NOT NULL
);
CREATE TABLE IF NOT EXISTS folders (
    id TEXT PRIMARY KEY, payload BLOB NOT NULL
);
CREATE TABLE IF NOT EXISTS assets (
    id TEXT PRIMARY KEY, size INTEGER NOT NULL CHECK(size >= 0)
);
CREATE TABLE IF NOT EXISTS uploads (
    id TEXT PRIMARY KEY, size INTEGER NOT NULL CHECK(size >= 0)
);
"""


@contextmanager
def lock(root, name, *, wait=True):
    root.mkdir(parents=True, exist_ok=True)
    with (root / name).open('a+b') as file:
        try:
            fcntl.flock(file, fcntl.LOCK_EX if wait else fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('the service is already running') from None
        yield


def connect(path):
    db = sqlite3.connect(path, timeout=15)
    db.execute('PRAGMA trusted_schema=OFF')
    return db


def identity():
    return secrets.token_urlsafe(24)


def file_hash(file):
    return hashlib.file_digest(file, 'sha256').hexdigest()


def sync_directory(path):
    directory = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


class Store:
    def __init__(self, root):
        self.library = Path(root) / LIBRARY
        self.database = self.library / DATABASE
        self.assets = self.library / ASSETS
        self.uploads = self.library / UPLOADS
        self.writes = Lock()

    def initialize(self):
        if not self.library.exists() and (self.library.parent / RESTORE_PENDING).exists():
            raise ValueError('complete the interrupted restore before starting the library')
        self.assets.mkdir(parents=True, exist_ok=True)
        self.uploads.mkdir(exist_ok=True)
        with closing(connect(self.database)) as db, db:
            db.execute('PRAGMA journal_mode=WAL')
            db.executescript(SCHEMA)
            db.execute(
                "INSERT OR IGNORE INTO metadata VALUES ('identity', ?)", (identity(),),
            )
        sync_directory(self.library)
        sync_directory(self.library.parent)

    def generation(self, db):
        return db.execute("SELECT value FROM metadata WHERE key='identity'").fetchone()[0]

    def authorized(self, db, token):
        digest = hashlib.sha256(token.encode('ascii')).digest()
        return db.execute('SELECT 1 FROM tokens WHERE digest=?', (digest,)).fetchone() is not None

    def create_token(self, label):
        token = secrets.token_urlsafe(32)
        digest = hashlib.sha256(token.encode('ascii')).digest()
        with closing(connect(self.database)) as db, db:
            try:
                db.execute('INSERT INTO tokens VALUES (?, ?)', (label, digest))
            except sqlite3.IntegrityError:
                raise ValueError('credential label already exists') from None
        return token

    def revoke_token(self, label):
        with closing(connect(self.database)) as db, db:
            if not db.execute('DELETE FROM tokens WHERE label=?', (label,)).rowcount:
                raise ValueError('credential label does not exist')

    def put_revision(self, db, identifier, payload, assets):
        with self.writes, db:
            old = db.execute(
                'SELECT payload FROM revisions WHERE id=?', (identifier,),
            ).fetchone()
            if old is not None:
                if old[0] != payload:
                    raise RequestError(409, 'revision_conflict')
                return
            for asset in assets:
                if self.asset_size(db, asset) is None:
                    raise RequestError(409, 'missing_asset')
            db.execute('INSERT INTO revisions (id, payload) VALUES (?, ?)', (identifier, payload))

    def revision_page(self, db, after, limit):
        next_cursor = after
        size = 0
        count = 0
        more = False
        for cursor, payload_size in db.execute(
            'SELECT seq, length(payload) FROM revisions WHERE seq>? ORDER BY seq LIMIT ?',
            (after, limit + 1),
        ):
            if count == limit or (count and size + payload_size + 1 > REVISION_PAGE_BUDGET):
                more = True
                break
            size += payload_size + (1 if count else 0)
            next_cursor = cursor
            count += 1
        rows = db.execute(
            'SELECT payload FROM revisions WHERE seq>? AND seq<=? ORDER BY seq',
            (after, next_cursor),
        )
        return rows, size, next_cursor, more

    def folders(self, db):
        catalog = {row[0]: json.loads(row[1]) for row in db.execute(
            'SELECT id, payload FROM folders ORDER BY id',
        )}
        return repair_folders(catalog)

    def put_folders(self, db, folders):
        with self.writes, db:
            for folder in folders:
                identifier = folder['id']
                old = db.execute(
                    'SELECT payload FROM folders WHERE id=?', (identifier,),
                ).fetchone()
                if old is None or folder_order(folder) > folder_order(json.loads(old[0])):
                    db.execute(
                        'INSERT INTO folders VALUES (?, ?) '
                        'ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
                        (identifier, json_bytes(folder)),
                    )

    def asset_size(self, db, asset):
        return self._published_size(asset, self._registered_size(db, asset))

    def _registered_size(self, db, asset):
        record = db.execute('SELECT size FROM assets WHERE id=?', (asset,)).fetchone()
        return None if record is None else record[0]

    def _published_size(self, asset, registered_size):
        if registered_size is None:
            return None
        try:
            info = (self.assets / asset).stat()
        except FileNotFoundError:
            return None
        if stat.S_ISREG(info.st_mode) and info.st_size == registered_size:
            return registered_size
        return None

    def asset_status(self, db, asset):
        with self.writes:
            complete, offset = self.recover_upload(db, asset)
            return complete, offset, offset if complete else self.upload_size(db, asset)

    def upload_size(self, db, asset):
        record = db.execute('SELECT size FROM uploads WHERE id=?', (asset,)).fetchone()
        return None if record is None else record[0]

    def append_asset(self, db, asset, offset, total, chunk):
        with self.writes:
            published, current = self.recover_upload(db, asset)
            if published:
                if offset != current:
                    raise stale_offset(current)
                if total != current or chunk:
                    raise RequestError(400, 'invalid_upload_length')
                return current

            staged = self.uploads / asset
            expected = self.upload_size(db, asset)
            restarting = offset == 0 and expected is not None and expected != total
            if current != offset and not restarting:
                raise stale_offset(current)
            if expected is not None and expected != total and not restarting:
                raise RequestError(400, 'invalid_upload_length')
            if restarting:
                current = 0
            if current + len(chunk) > total or (not chunk and current != total):
                raise RequestError(400, 'invalid_upload_length')
            if restarting:
                staged.unlink(missing_ok=True)
                sync_directory(self.uploads)
            if total != expected:
                with db:
                    db.execute(
                        'INSERT INTO uploads VALUES (?, ?) '
                        'ON CONFLICT(id) DO UPDATE SET size=excluded.size',
                        (asset, total),
                    )

            with staged.open('ab') as file:
                file.write(chunk)
                file.flush()
                os.fsync(file.fileno())
            sync_directory(self.uploads)
            current += len(chunk)
            if current == total and not self.publish_upload(db, asset, staged, current):
                raise RequestError(400, 'asset_hash_mismatch')
            return current

    def recover_upload(self, db, asset):
        registered_size = self._registered_size(db, asset)
        size = self._published_size(asset, registered_size)
        if size is not None:
            return True, size

        # The last chunk and rename are durable before SQLite records publication.
        target = self.assets / asset
        if registered_size is None and target.exists():
            with target.open('rb') as file:
                if file_hash(file) != asset:
                    raise OSError('asset on disk has an invalid digest')
                size = os.fstat(file.fileno()).st_size
                os.fsync(file.fileno())
            sync_directory(self.assets)
            sync_directory(self.uploads)
            self.register_asset(db, asset, size)
            return True, size

        staged = self.uploads / asset
        try:
            size = staged.stat().st_size
        except FileNotFoundError:
            return False, 0
        if size == self.upload_size(db, asset):
            if self.publish_upload(db, asset, staged, size):
                return True, size
            return False, 0
        return False, size

    def publish_upload(self, db, asset, staged, size):
        with staged.open('rb') as file:
            verified = file_hash(file) == asset
            if verified:
                os.fsync(file.fileno())
        if not verified:
            staged.unlink()
            sync_directory(self.uploads)
            with db:
                db.execute('DELETE FROM uploads WHERE id=?', (asset,))
            return False
        staged.rename(self.assets / asset)
        sync_directory(self.assets)
        sync_directory(self.uploads)
        self.register_asset(db, asset, size)
        return True

    def register_asset(self, db, asset, size):
        with db:
            db.execute(
                'INSERT INTO assets VALUES (?, ?) '
                'ON CONFLICT(id) DO UPDATE SET size=excluded.size',
                (asset, size),
            )
            db.execute('DELETE FROM uploads WHERE id=?', (asset,))


def stale_offset(offset):
    return RequestError(409, 'upload_offset', {'Upload-Offset': str(offset)})
