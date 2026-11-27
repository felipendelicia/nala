from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import logging
import os
import re
import shutil
import sqlite3
from time import monotonic
from urllib.parse import parse_qs, urlsplit

from .protocol import (
    ASSET_ID, MAX_CHUNK, MAX_JSON, RequestError, decimal,
    array_value, folder_data, json_bytes, object_value, revision_data,
)
from .storage import connect

ASSET_ROUTE = re.compile(r'/v1/assets/(' + ASSET_ID.pattern + ')')
ROUTE_NAMES = {
    '/v1/identity': 'identity',
    '/v1/revisions': 'revisions',
    '/v1/folders': 'folders',
}


class Server(ThreadingHTTPServer):
    def __init__(self, address, store):
        self.store = store
        super().__init__(address, Handler)

    def get_request(self):
        client, address = super().get_request()
        client.settimeout(30)
        return client, address


class Handler(BaseHTTPRequestHandler):
    server_version = 'Nala'
    sys_version = ''

    def log_message(self, format, *args):
        # Do not log untrusted paths or authentication data.
        return

    def do_GET(self):
        self.dispatch()

    def do_HEAD(self):
        self.dispatch()

    def do_PUT(self):
        self.dispatch()

    def do_PATCH(self):
        self.dispatch()

    def dispatch(self):
        started = monotonic()
        route_name = 'unknown'
        try:
            parts = urlsplit(self.path)
            route_name = ('assets' if ASSET_ROUTE.fullmatch(parts.path)
                          else ROUTE_NAMES.get(parts.path, 'unknown'))
            with closing(connect(self.server.store.database)) as db:
                self.route(db, parts.path, parts.query)
        except RequestError as error:
            if error.status in (409, 413) and error.code != 'upload_offset':
                self.log_sync_failure(route_name, started, error.status, error.code)
            self.respond_json(error.status, {'error': error.code}, error.headers)
        except (ValueError, OverflowError, RecursionError):
            self.respond_json(400, {'error': 'invalid_request'})
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            return
        except (OSError, sqlite3.Error) as error:
            self.log_sync_failure(route_name, started, 500, type(error).__name__)
            self.respond_json(500, {'error': 'server_error'})

    def log_sync_failure(self, route_name, started, status, reason):
        # Route categories and controlled reason codes omit request data.
        logging.warning(
            'Nala sync %s %s: status=%d reason=%s duration_ms=%d',
            self.command, route_name, status, reason, (monotonic() - started) * 1000,
        )

    def route(self, db, path, query):
        store = self.server.store
        auth = re.fullmatch(
            r'Bearer ([A-Za-z0-9_-]{43})', self.headers.get('Authorization', ''),
            re.IGNORECASE | re.ASCII,
        )
        if auth is None or not store.authorized(db, auth.group(1)):
            raise RequestError(401, 'unauthorized', {'WWW-Authenticate': 'Bearer'})

        if path == '/v1/identity' and self.command == 'GET':
            self.respond_json(200, {'id': store.generation(db)})
            return

        if self.headers.get('X-Nala-Server') != store.generation(db):
            raise RequestError(409, 'server_changed')

        if path == '/v1/revisions':
            if self.command == 'GET':
                self.revisions(db, query)
                return
            if self.command == 'PUT':
                store.put_revision(db, *revision_data(self.read_json()))
                self.send_empty()
                return

        if path == '/v1/folders':
            if self.command == 'GET':
                self.respond_json(200, {'items': store.folders(db)})
                return
            if self.command == 'PUT':
                body = self.read_json()
                items = array_value(body['items']) if 'items' in body else [body]
                store.put_folders(db, [folder_data(item) for item in items])
                self.send_empty()
                return

        match = ASSET_ROUTE.fullmatch(path)
        if match is not None:
            self.asset(db, match[1])
            return
        raise RequestError(404, 'not_found')

    def read_body(self, maximum):
        lengths = self.headers.get_all('Content-Length', [])
        if self.headers.get('Transfer-Encoding') is not None or len(lengths) != 1:
            raise RequestError(400, 'invalid_content_length')
        length = decimal(lengths[0])
        if length > maximum:
            raise RequestError(413, 'request_too_large')
        body = self.rfile.read(length)
        if len(body) != length:
            raise RequestError(400, 'incomplete_request')
        return body

    def read_json(self):
        return object_value(json.loads(self.read_body(MAX_JSON).decode('utf-8')))

    def revisions(self, db, query):
        params = parse_qs(query, keep_blank_values=True, max_num_fields=2, strict_parsing=True)
        if set(params) - {'after', 'limit'} or any(len(value) != 1 for value in params.values()):
            raise RequestError(400, 'invalid_query')
        after = decimal(params.get('after', ['0'])[0])
        limit = decimal(params.get('limit', ['50'])[0])
        if not 1 <= limit <= 500:
            raise RequestError(400, 'invalid_limit')
        rows, size, cursor, more = self.server.store.revision_page(db, after, limit)
        opening = b'{"items":['
        ending = b'],' + json_bytes({'next': cursor, 'more': more})[1:]
        self.begin_response(200, len(opening) + size + len(ending), 'application/json')
        self.wfile.write(opening)
        for index, (payload,) in enumerate(rows):
            if index:
                self.wfile.write(b',')
            self.wfile.write(payload)
        self.wfile.write(ending)

    def asset(self, db, identifier):
        store = self.server.store
        if self.command == 'HEAD':
            complete, offset, total = store.asset_status(db, identifier)
            headers = {'Upload-Offset': str(offset)}
            if total is not None:
                headers['Upload-Length'] = str(total)
            self.begin_response(
                200 if complete else 404, offset if complete else 0,
                'application/octet-stream', headers,
            )
            return
        if self.command == 'PATCH':
            offset = decimal(self.headers.get('Upload-Offset'))
            total = decimal(self.headers.get('Upload-Length'))
            accepted = store.append_asset(db, identifier, offset, total, self.read_body(MAX_CHUNK))
            self.send_empty({'Upload-Offset': str(accepted)})
            return
        if self.command != 'GET':
            raise RequestError(404, 'not_found')

        size = store.asset_size(db, identifier)
        if size is None:
            raise RequestError(404, 'asset_not_found')
        start = 0
        status = 200
        headers = {'Accept-Ranges': 'bytes'}
        range_value = self.headers.get('Range')
        if range_value is not None:
            match = re.fullmatch(r'bytes=([0-9]{1,19})-', range_value)
            if match is None or int(match[1]) >= size:
                raise RequestError(416, 'range_not_satisfiable', {'Content-Range': f'bytes */{size}'})
            start = int(match[1])
            status = 206
            headers['Content-Range'] = f'bytes {start}-{size - 1}/{size}'
        try:
            file = (store.assets / identifier).open('rb')
        except FileNotFoundError:
            raise RequestError(404, 'asset_not_found') from None
        with file:
            if os.fstat(file.fileno()).st_size != size:
                raise RequestError(404, 'asset_not_found')
            file.seek(start)
            self.begin_response(status, size - start, 'application/octet-stream', headers)
            shutil.copyfileobj(file, self.wfile, length=1024 * 1024)

    def begin_response(self, status, size, content_type=None, headers=None):
        self.send_response(status)
        if size is not None:
            self.send_header('Content-Length', str(size))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Connection', 'close')
        if content_type is not None:
            self.send_header('Content-Type', content_type)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.close_connection = True

    def send_empty(self, headers=None):
        self.begin_response(204, None, headers=headers)

    def respond_json(self, status, data, headers=None):
        body = json_bytes(data)
        self.begin_response(status, len(body), 'application/json', headers)
        if self.command != 'HEAD':
            self.wfile.write(body)
