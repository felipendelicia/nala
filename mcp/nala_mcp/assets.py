import hashlib
import os
import re
import stat
from pathlib import Path


MAX_ASSET_BYTES = 64 * 1024 * 1024


class AssetError(ValueError):
    pass


class AssetMissing(AssetError):
    pass


def asset_bytes(assets: Path, asset_id: object) -> bytes:
    if not isinstance(asset_id, str) or not re.fullmatch(r'[0-9a-f]{64}', asset_id):
        raise AssetError('Identificador de recurso inválido.')
    try:
        directory = os.open(assets, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            fd = os.open(asset_id, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        finally:
            os.close(directory)
        with os.fdopen(fd, 'rb') as stream:
            metadata = os.fstat(stream.fileno())
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > MAX_ASSET_BYTES:
                raise AssetError('Recurso local inválido o demasiado grande.')
            contents = stream.read(MAX_ASSET_BYTES + 1)
    except FileNotFoundError as error:
        raise AssetMissing('El recurso todavía no está disponible localmente.') from error
    except OSError as error:
        raise AssetError('No se pudo leer el recurso local.') from error
    if len(contents) > MAX_ASSET_BYTES or hashlib.sha256(contents).hexdigest() != asset_id:
        raise AssetError('El recurso local está dañado o es demasiado grande.')
    return contents
