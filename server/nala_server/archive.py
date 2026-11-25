from contextlib import closing
import gzip
import json
import os
from pathlib import Path
import shutil
import tarfile
import tempfile

from .protocol import ASSET_ID, folder_data, revision_data
from .storage import (
    ASSETS, DATABASE, LIBRARY, LOCKS, RESTORE_PENDING, UPLOADS,
    connect, file_hash, identity, sync_directory,
)

TABLES = {'assets', 'folders', 'metadata', 'revisions', 'tokens', 'uploads'}


def backup(store, archive):
    archive = archive.resolve()
    if archive.is_relative_to(store.library.parent.resolve()):
        raise ValueError('choose a backup path outside the data directory')
    if not store.database.is_file():
        raise ValueError('the data directory does not contain a library')

    with tempfile.TemporaryDirectory(prefix='.nala-backup-', dir=archive.parent) as temporary:
        workspace = Path(temporary)
        snapshot = workspace / DATABASE
        with closing(connect(store.database)) as source, closing(connect(snapshot)) as saved:
            source.backup(saved)
            saved.execute('PRAGMA journal_mode=DELETE')
            with saved:
                saved.execute('DELETE FROM uploads')
            with (workspace / 'archive').open('wb') as output:
                with tarfile.open(fileobj=output, mode='w:gz') as package:
                    package.add(snapshot, arcname=DATABASE, recursive=False)
                    for identifier, size in saved.execute('SELECT id, size FROM assets ORDER BY id'):
                        if not ASSET_ID.fullmatch(identifier):
                            raise ValueError('an asset in the library is missing or damaged')
                        with (store.assets / identifier).open('rb') as file:
                            info = package.gettarinfo(arcname=f'{ASSETS}/{identifier}', fileobj=file)
                            if not info.isreg() or info.size != size or file_hash(file) != identifier:
                                raise ValueError('an asset in the library is missing or damaged')
                            file.seek(0)
                            package.addfile(info, file)
                output.flush()
                os.fsync(output.fileno())
        os.replace(workspace / 'archive', archive)
        sync_directory(archive.parent)


def restore(store, archive):
    root = store.library.parent
    if any(path.name not in LOCKS | {RESTORE_PENDING} for path in root.iterdir()):
        raise ValueError('restore requires an empty data directory')

    pending = root / RESTORE_PENDING
    marker = pending / '.nala-restore'
    if pending.is_symlink():
        raise ValueError('restore staging directory cannot be a symbolic link')
    if pending.exists():
        if marker.is_file() and not marker.is_symlink():
            shutil.rmtree(pending)
        else:
            pending.rmdir()
    pending.mkdir()
    try:
        marker.touch(exist_ok=False)
        sync_directory(pending)
        sync_directory(root)
        candidate = pending / LIBRARY
        (candidate / ASSETS).mkdir(parents=True)
        (candidate / UPLOADS).mkdir()
        sizes = unpack(archive, candidate)
        verify_database(candidate / DATABASE, sizes)
        sync_directory(candidate / ASSETS)
        sync_directory(candidate / UPLOADS)
        sync_directory(candidate)
        candidate.rename(store.library)
        sync_directory(root)
    finally:
        shutil.rmtree(pending)


def unpack(archive, candidate):
    seen = set()
    sizes = {}
    with gzip.open(archive, 'rb') as compressed, tarfile.open(fileobj=compressed, mode='r|') as package:
        for member in package:
            parts = member.name.split('/')
            is_asset = (
                len(parts) == 2 and parts[0] == ASSETS and ASSET_ID.fullmatch(parts[1])
            )
            if (
                not member.isreg() or member.name in seen or
                (member.name != DATABASE and not is_asset)
            ):
                raise ValueError('backup contains an unexpected entry')
            with package.extractfile(member) as source, (candidate / member.name).open('xb+') as file:
                shutil.copyfileobj(source, file, length=1024 * 1024)
                file.flush()
                if is_asset:
                    file.seek(0)
                    if file_hash(file) != parts[1]:
                        raise ValueError('backup contains a damaged asset')
                    sizes[parts[1]] = member.size
                os.fsync(file.fileno())
            seen.add(member.name)
        # tar ends before the gzip trailer, whose checksum guards the archive.
        while compressed.read(1024 * 1024):
            pass
    if DATABASE not in seen:
        raise ValueError('backup is missing its database')
    return sizes


def verify_database(path, sizes):
    with closing(connect(path)) as db:
        if db.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
            raise ValueError('backup database is damaged')
        objects = db.execute(
            "SELECT type, name FROM sqlite_schema WHERE name NOT LIKE 'sqlite_autoindex_%'",
        )
        if set(objects) != {('table', name) for name in TABLES}:
            raise ValueError('backup database has an unexpected schema')
        if dict(db.execute('SELECT id, size FROM assets')) != sizes:
            raise ValueError('backup database and assets do not match')
        for identifier, payload in db.execute('SELECT id, payload FROM revisions'):
            parsed_id, _, assets = revision_data(json.loads(payload))
            if parsed_id != identifier or not assets.issubset(sizes):
                raise ValueError('backup contains an invalid revision')
        for identifier, payload in db.execute('SELECT id, payload FROM folders'):
            if folder_data(json.loads(payload))['id'] != identifier:
                raise ValueError('backup contains an invalid folder')
        db.execute('PRAGMA secure_delete=ON')
        with db:
            rotated = db.execute("UPDATE metadata SET value=? WHERE key='identity'", (identity(),))
            if rotated.rowcount != 1:
                raise ValueError('backup is missing its identity')
            # Restoring an old snapshot must never reactivate a revoked credential.
            db.execute('DELETE FROM tokens')
            db.execute('DELETE FROM uploads')
        db.execute('PRAGMA journal_mode=DELETE')
