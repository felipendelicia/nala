import argparse
import os
from pathlib import Path
import sqlite3
import sys
import tarfile

from .archive import backup, restore
from .http_service import Server
from .storage import Store, lock


def parse_args():
    parser = argparse.ArgumentParser(prog='nala-server', description='Private Nala sync server')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('serve')
    for command in ('token-create', 'token-revoke'):
        commands.add_parser(command).add_argument('label')
    for command in ('backup', 'restore'):
        commands.add_parser(command).add_argument('archive', type=Path)
    return parser.parse_args()


def serve(root, store):
    with lock(root, '.serve.lock', wait=False):
        with lock(root, '.operation.lock'):
            store.initialize()
        address = os.environ.get('NALA_BIND', '0.0.0.0'), int(os.environ.get('NALA_PORT', '8080'))
        with Server(address, store) as server:
            server.serve_forever()


def run(args):
    root = Path(os.environ.get('NALA_DATA_DIR', 'data'))
    store = Store(root)
    if args.command == 'serve':
        serve(root, store)
        return
    if args.command == 'restore':
        with lock(root, '.serve.lock', wait=False), lock(root, '.operation.lock'):
            restore(store, args.archive)
        return

    with lock(root, '.operation.lock'):
        if args.command == 'backup':
            backup(store, args.archive)
            return
        label = args.label.strip()
        if not label or '\x00' in label:
            raise ValueError('choose a non-empty credential label')
        if args.command == 'token-create':
            store.initialize()
            print(store.create_token(label))
        else:
            if not store.database.is_file():
                raise ValueError('the data directory does not contain a library')
            store.revoke_token(label)


def main():
    os.umask(0o077)
    args = parse_args()
    try:
        run(args)
    except KeyboardInterrupt:
        return 0
    except (OSError, ValueError, sqlite3.Error, tarfile.TarError, RecursionError, EOFError) as error:
        print(f'nala-server: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
