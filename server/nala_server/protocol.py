import datetime
import json
import re

ASSET_ID = re.compile(r'[a-f0-9]{64}')
MAX_CHUNK = 4 * 1024 * 1024
MAX_JSON = 64 * 1024 * 1024
MAX_INTEGER = (1 << 63) - 1


class RequestError(Exception):
    def __init__(self, status, code, headers=None):
        super().__init__(code)
        self.status = status
        self.code = code
        self.headers = headers or {}


def json_bytes(value, *, sort_keys=False):
    return json.dumps(
        value, ensure_ascii=False, allow_nan=False,
        separators=(',', ':'), sort_keys=sort_keys,
    ).encode('utf-8')


def decimal(value):
    if value is None or not re.fullmatch(r'[0-9]{1,19}', value):
        raise RequestError(400, 'invalid_number')
    number = int(value)
    if number > MAX_INTEGER:
        raise RequestError(400, 'invalid_number')
    return number


def object_value(value):
    if not isinstance(value, dict):
        raise ValueError('expected an object')
    return value


def array_value(value, *, default=None):
    if value is None and default is not None:
        return default
    if not isinstance(value, list):
        raise ValueError('expected an array')
    return value


def nonempty(value):
    if not isinstance(value, str) or not value.strip():
        raise ValueError('expected a non-empty string')
    return value


def timestamp(value):
    result = datetime.datetime.fromisoformat(nonempty(value))
    if result.tzinfo is None:
        raise ValueError('expected a timestamp with offset')
    return result.astimezone(datetime.timezone.utc)


def asset_ids(notebook):
    def add(value, *, required=False):
        if value is None and not required:
            return
        if not isinstance(value, str) or not ASSET_ID.fullmatch(value):
            raise ValueError('invalid asset ID')
        ids.add(value)

    ids = set()
    add(notebook.get('coverAssetId'))
    for recording in array_value(notebook.get('recordings'), default=[]):
        add(object_value(recording).get('assetId'), required=True)
    for item in array_value(notebook.get('pages')):
        page = object_value(item)
        add(object_value(page.get('background')).get('assetId'))
        for comment in array_value(page.get('comments'), default=[]):
            add(object_value(comment).get('audioAssetId'))
        for entry in array_value(page.get('objects'), default=[]):
            obj = object_value(entry)
            add(obj.get('assetId'))
            add(obj.get('originalAssetId'))
    return ids


def revision_data(value):
    identifier = nonempty(value.get('id'))
    if type(value.get('schemaVersion')) is not int or value['schemaVersion'] != 1:
        raise ValueError('invalid revision version')
    nonempty(value.get('deviceId'))
    parent = value.get('parentId')
    if parent is not None and nonempty(parent) == identifier:
        raise ValueError('cyclic revision')
    timestamp(value.get('createdAt'))
    notebook = object_value(value.get('notebook'))
    if type(notebook.get('schemaVersion')) is not int or notebook['schemaVersion'] != 1:
        raise ValueError('invalid notebook version')
    nonempty(notebook.get('id'))
    nonempty(notebook.get('title'))
    if not isinstance(notebook.get('subject'), str):
        raise ValueError('invalid notebook subject')
    if notebook.get('folderId') is not None:
        nonempty(notebook['folderId'])
    timestamp(notebook.get('updatedAt'))
    if not array_value(notebook.get('pages')):
        raise ValueError('notebook has no pages')
    return identifier, json_bytes(value, sort_keys=True), asset_ids(notebook)


def folder_data(value):
    folder = object_value(value)
    identifier = folder.get('id')
    name = nonempty(folder.get('name'))
    parent = folder.get('parentId')
    deleted = folder.get('deleted', False)
    if not isinstance(identifier, str) or not identifier:
        raise ValueError('invalid folder ID')
    if (parent is not None and not isinstance(parent, str)) or parent == identifier:
        raise ValueError('invalid folder parent')
    if deleted is None:
        deleted = False
    if type(deleted) is not bool:
        raise ValueError('invalid folder deletion flag')
    updated = timestamp(folder.get('updatedAt'))
    timespec = 'microseconds' if updated.microsecond % 1000 else 'milliseconds'
    return {
        'id': identifier, 'name': name, 'parentId': parent,
        'updatedAt': updated.isoformat(timespec=timespec).replace('+00:00', 'Z'),
        'deleted': deleted,
    }


def folder_order(folder):
    # Dart compares JSON strings in UTF-16 code unit order at equal timestamps.
    return timestamp(folder['updatedAt']), json_bytes(folder).decode().encode('utf-16-be')


def repair_folders(catalog):
    # The stored winners keep their original parents so an out-of-order upload
    # can still link children when the parent arrives.
    visited = set()
    for start in sorted(catalog, key=lambda value: value.encode('utf-16-be')):
        path = {}
        cursor = start
        while cursor is not None and cursor not in visited and not catalog[cursor]['deleted']:
            if cursor in path:
                cycle = list(path)[path[cursor]:]
                root = min(cycle, key=lambda value: value.encode('utf-16-be'))
                catalog[root]['parentId'] = None
                break
            path[cursor] = len(path)
            parent = catalog[cursor]['parentId']
            if parent is not None and (parent not in catalog or catalog[parent]['deleted']):
                catalog[cursor]['parentId'] = None
                break
            cursor = parent
        visited.update(path)
    return list(catalog.values())
