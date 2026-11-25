import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/folders.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/notebook_recording.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/sync/remote_store.dart';
import 'package:apuntes/sync/server_remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:apuntes/sync/sync_state.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fixtures.dart';

final _base = Uri.parse('https://notes.example/nala/');

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Revision _revision(String id, [String? parent]) => Revision(
  id: id,
  parentId: parent,
  deviceId: 'tablet',
  createdAt: DateTime.utc(2026, 11, 24),
  notebook: fixtureNotebook(),
);

Object? _encodedRevision(String id, [String? parent]) =>
    jsonDecode(NotebookCodec.encodeRevision(_revision(id, parent)));

class _FileOnlyAssetStore extends FileAssetStore {
  _FileOnlyAssetStore(super.directory);

  @override
  Future<Uint8List> read(String assetId) =>
      throw StateError('Sync loaded the entire recording into memory');

  @override
  Future<String> put(Uint8List bytes) =>
      throw StateError('Sync buffered the entire downloaded recording');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory library;

  setUp(() async {
    library = await Directory.systemTemp.createTemp('nala-server-store-');
  });
  tearDown(() async => library.delete(recursive: true));

  ServerRemoteStore connect(
    http.Client client, {
    String serverId = 'first',
    String cursorName = 'cursor.json',
  }) {
    final store = ServerRemoteStore(
      baseUrl: _base,
      token: 'device-secret',
      serverId: serverId,
      cursorPath: '${library.path}/$cursorName',
      client: client,
    );
    addTearDown(store.close);
    return store;
  }

  test('identity requires HTTPS and never follows an HTTP redirect', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url, Uri.parse('https://notes.example/nala/v1/identity'));
      expect(request.headers['authorization'], 'Bearer device-secret');
      expect(request.followRedirects, isFalse);
      return http.Response(
        '',
        307,
        headers: {'location': 'https://elsewhere.example/identity'},
      );
    });

    await expectLater(
      ServerRemoteStore.identify(
        baseUrl: Uri.parse('http://notes.example'),
        token: 'device-secret',
        client: client,
      ),
      throwsFormatException,
    );
    await expectLater(
      ServerRemoteStore.identify(
        baseUrl: _base,
        token: 'device-secret',
        client: client,
      ),
      throwsA(isA<HttpException>()),
    );
    expect(requests, 1);
  });

  test(
    'the failed page is replayed after restart under the same server ID',
    () async {
      final afters = <String>[];
      MockClient server() => MockClient((request) async {
        final after = request.url.queryParameters['after']!;
        afters.add(after);
        expect(request.url.path, '/nala/v1/revisions');
        expect(request.headers['x-nala-server'], 'first');
        return switch (after) {
          '0' => _json({
            'items': [_encodedRevision('base')],
            'next': 1,
            'more': true,
          }),
          '1' => _json({
            'items': [
              _encodedRevision('followup', 'base'),
              _encodedRevision('finish', 'followup'),
            ],
            'next': 3,
            'more': false,
          }),
          '3' => _json({'items': [], 'next': 3, 'more': false}),
          _ => throw StateError('Unexpected cursor $after'),
        };
      });

      final first = connect(server());
      final accepted = <String>[];
      await expectLater(
        first.pullRevisions((revision) async {
          if (revision.id == 'finish') throw StateError('Catalog write failed');
          accepted.add(revision.id);
        }),
        throwsStateError,
      );
      first.close();

      final reopened = connect(server());
      await reopened.pullRevisions(
        (revision) async => accepted.add(revision.id),
      );
      await reopened.pullRevisions((_) async => fail('Unexpected revision'));
      expect(accepted, ['base', 'followup', 'followup', 'finish']);
      expect(afters, ['0', '1', '1', '3']);

      final restored = connect(
        MockClient((request) async {
          expect(request.headers['x-nala-server'], 'restored');
          expect(request.url.queryParameters['after'], '0');
          return _json({'items': [], 'next': 0, 'more': false});
        }),
        serverId: 'restored',
      );
      await restored.pullRevisions((_) async => fail('Unexpected revision'));
    },
  );

  test(
    'pull rejects a non-advancing page without accepting its revisions',
    () async {
      final store = connect(
        MockClient(
          (_) async => _json({
            'items': [_encodedRevision('base')],
            'next': 0,
            'more': true,
          }),
        ),
      );
      await expectLater(
        store.pullRevisions((_) async => fail('Invalid page was accepted')),
        throwsFormatException,
      );
    },
  );

  test('invalid credentials require the device to reconnect', () async {
    final store = connect(
      MockClient((_) async => _json({'error': 'unauthorized'}, 401)),
    );
    await expectLater(
      store.listFolders(),
      throwsA(isA<RemoteSignInRequired>()),
    );
  });

  test(
    'a bodyless HEAD conflict checks for a different server generation',
    () async {
      final paths = <String>[];
      final store = connect(
        MockClient((request) async {
          paths.add(request.url.path);
          if (request.method == 'HEAD') return http.Response('', 409);
          expect(request.headers['x-nala-server'], isNull);
          return _json({'id': 'restored'});
        }),
      );
      await expectLater(
        store.hasAsset('a' * 64),
        throwsA(isA<RemoteServerChanged>()),
      );
      expect(paths, ['/nala/v1/assets/${'a' * 64}', '/nala/v1/identity']);
    },
  );

  test(
    'a changed server pauses synchronization before sending local edits',
    () async {
      final requests = <String>[];
      final store = connect(
        MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          return _json({'error': 'server_changed'}, 409);
        }),
      );
      final repository = await SqliteNotebookRepository.open(
        '${library.path}/library.db',
      );
      addTearDown(repository.close);
      await repository.commit(_revision('unsent'));
      final engine = SyncEngine(
        repository: repository,
        assets: FileAssetStore('${library.path}/assets'),
        remote: store,
      );
      addTearDown(engine.dispose);

      await engine.synchronize();

      expect(engine.status.phase, SyncPhase.needsSignIn);
      expect(engine.status.message, contains('cambió'));
      expect((await repository.pending()).single.id, 'unsent');
      expect(requests, ['GET /nala/v1/folders']);
    },
  );

  test('folder hierarchy and deletions are published in one request', () async {
    final writes = <Object?>[];
    final store = connect(
      MockClient((request) async {
        if (request.method == 'PUT' && request.url.path.endsWith('/folders')) {
          writes.add(jsonDecode(request.body));
          return http.Response('', 204);
        }
        return _json({
          'items': [],
          if (request.url.path.endsWith('/revisions')) ...{
            'next': 0,
            'more': false,
          },
        });
      }),
    );
    final repository = await SqliteNotebookRepository.open(
      '${library.path}/library.db',
    );
    addTearDown(repository.close);
    for (final (id, parent) in [
      ('parent', null),
      ('child', 'parent'),
      ('removed', null),
    ]) {
      await repository.saveFolder(
        NoteFolder(
          id: id,
          name: id,
          parentId: parent,
          updatedAt: DateTime.utc(2026),
        ),
      );
    }
    await repository.deleteFolder('removed');
    final engine = SyncEngine(
      repository: repository,
      assets: FileAssetStore('${library.path}/assets'),
      remote: store,
    );
    addTearDown(engine.dispose);

    await engine.synchronize();

    expect(engine.status.phase, SyncPhase.synced);
    expect(writes, hasLength(1));
    final body = writes.single as Map<String, dynamic>;
    final folders = (body['items'] as List).cast<Map<String, dynamic>>();
    expect(
      {for (final folder in folders) folder['id']: folder['parentId']},
      {'parent': null, 'child': 'parent', 'removed': null},
    );
    expect(
      folders.singleWhere((folder) => folder['id'] == 'removed')['deleted'],
      isTrue,
    );
  });

  test(
    'SQLite can read one retained revision with its exact identity',
    () async {
      final repository = await SqliteNotebookRepository.open(
        '${library.path}/library.db',
      );
      addTearDown(repository.close);
      await repository.acceptRemote(_revision('base'));
      await repository.acceptRemote(_revision('followup', 'base'));

      final revision = await repository.lookupRevision('doc-1', 'followup');

      expect(revision?.id, 'followup');
      expect(revision?.parentId, 'base');
      expect(revision?.deviceId, 'tablet');
      expect(await repository.lookupRevision('other', 'followup'), isNull);
    },
  );

  test(
    'a reopened upload resumes a staged chunk and can be repeated',
    () async {
      const chunkSize = 4 * 1024 * 1024;
      final bytes = Uint8List(chunkSize + 17);
      bytes[chunkSize] = 42;
      final id = sha256.convert(bytes).toString();
      final staged = BytesBuilder();
      final offsets = <int>[];
      var interrupted = false;
      MockClient server() => MockClient((request) async {
        expect(request.url.path, '/nala/v1/assets/$id');
        if (request.method == 'HEAD') {
          return http.Response(
            '',
            staged.length == bytes.length ? 200 : 404,
            headers: {'upload-offset': '${staged.length}'},
          );
        }
        expect(request.method, 'PATCH');
        final offset = int.parse(request.headers['upload-offset']!);
        offsets.add(offset);
        expect(offset, staged.length);
        expect(request.headers['upload-length'], '${bytes.length}');
        expect(request.bodyBytes.length, lessThanOrEqualTo(chunkSize));
        if (offset == chunkSize && !interrupted) {
          interrupted = true;
          throw http.ClientException('Connection ended');
        }
        staged.add(request.bodyBytes);
        return http.Response(
          '',
          204,
          headers: {'upload-offset': '${staged.length}'},
        );
      });

      final first = connect(server());
      await expectLater(
        first.putAsset(id, bytes),
        throwsA(isA<http.ClientException>()),
      );
      first.close();
      final reopened = connect(server());
      await reopened.putAsset(id, bytes);
      await reopened.putAsset(id, bytes);
      expect(offsets, [0, chunkSize, chunkSize]);
      expect(sha256.convert(staged.takeBytes()).toString(), id);
    },
  );

  test('an upload restarts at zero if its staged length differs', () async {
    final bytes = Uint8List.fromList([11, 22, 33, 44, 55]);
    final id = sha256.convert(bytes).toString();
    var published = false;
    final store = connect(
      MockClient((request) async {
        if (request.method == 'HEAD') {
          return http.Response(
            '',
            404,
            headers: {'upload-offset': '2', 'upload-length': '19'},
          );
        }
        expect(request.method, 'PATCH');
        expect(request.headers['upload-offset'], '0');
        expect(request.headers['upload-length'], '5');
        expect(request.bodyBytes, bytes);
        published = true;
        return http.Response('', 204, headers: {'upload-offset': '5'});
      }),
    );

    await store.putAsset(id, bytes);
    expect(published, isTrue);
  });

  test(
    'an interrupted download requests the remaining bytes after restart',
    () async {
      final bytes = Uint8List.fromList([11, 22, 33, 44, 55]);
      final id = sha256.convert(bytes).toString();
      final first = connect(
        MockClient.streaming((request, _) async {
          expect(request.headers['range'], isNull);
          Stream<List<int>> interrupted() async* {
            yield bytes.sublist(0, 2);
            throw http.ClientException('Connection ended');
          }

          return http.StreamedResponse(interrupted(), 200, contentLength: 5);
        }),
      );
      await expectLater(
        first.readAsset(id),
        throwsA(isA<http.ClientException>()),
      );
      first.close();

      final reopened = connect(
        MockClient.streaming((request, _) async {
          expect(request.headers['range'], 'bytes=2-');
          return http.StreamedResponse(
            Stream.value(bytes.sublist(2)),
            206,
            contentLength: 3,
            headers: {'content-range': 'bytes 2-4/5'},
          );
        }),
      );
      expect(await reopened.readAsset(id), bytes);
    },
  );

  test(
    'a completely downloaded asset must match its advertised hash',
    () async {
      final store = connect(
        MockClient(
          (_) async => http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-length': '3'},
          ),
        ),
      );
      await expectLater(store.readAsset('a' * 64), throwsFormatException);
    },
  );

  test('sync uploads and repairs a large recording through files', () async {
    const block = 4 * 1024 * 1024;
    final bytes = Uint8List(block + 25)..[block] = 31;
    final sourceAssets = '${library.path}/source-assets';
    final targetAssets = '${library.path}/target-assets';
    final id = await FileAssetStore(sourceAssets).put(bytes);
    await Directory(targetAssets).create();
    await File('$targetAssets/$id').writeAsBytes([0, 1, 2]);
    final revision = Revision(
      id: 'with-recording',
      parentId: null,
      deviceId: 'tablet',
      createdAt: DateTime.utc(2026, 11, 24),
      notebook: fixtureNotebook().copyWith(
        recordings: [
          NotebookRecording(
            id: 'lecture',
            title: 'Álgebra',
            assetId: id,
            durationMs: 40000,
            createdAt: DateTime.utc(2026, 11, 24),
          ),
        ],
      ),
    );

    final staged = BytesBuilder();
    final chunks = <int>[];
    Object? published;
    MockClient server() => MockClient((request) async {
      if (request.url.path.endsWith('/folders')) return _json({'items': []});
      if (request.url.path.endsWith('/revisions')) {
        if (request.method == 'PUT') {
          expect(staged.length, bytes.length);
          published = jsonDecode(request.body);
          return http.Response('', 204);
        }
        final after = int.parse(request.url.queryParameters['after']!);
        final hasNew = published != null && after == 0;
        return _json({
          'items': [if (hasNew) published],
          'next': hasNew ? 1 : after,
          'more': false,
        });
      }
      expect(request.url.path, '/nala/v1/assets/$id');
      if (request.method == 'HEAD') {
        return http.Response(
          '',
          staged.length == bytes.length ? 200 : 404,
          headers: {'upload-offset': '${staged.length}'},
        );
      }
      if (request.method == 'PATCH') {
        expect(request.headers['upload-offset'], '${staged.length}');
        chunks.add(request.bodyBytes.length);
        staged.add(request.bodyBytes);
        return http.Response(
          '',
          204,
          headers: {'upload-offset': '${staged.length}'},
        );
      }
      expect(request.method, 'GET');
      return http.Response.bytes(staged.toBytes(), 200);
    });

    final source = await SqliteNotebookRepository.open(
      '${library.path}/source.db',
    );
    final target = await SqliteNotebookRepository.open(
      '${library.path}/target.db',
    );
    addTearDown(source.close);
    addTearDown(target.close);
    await source.commit(revision);
    final uploader = SyncEngine(
      repository: source,
      assets: _FileOnlyAssetStore(sourceAssets),
      remote: connect(server()),
    );
    final downloader = SyncEngine(
      repository: target,
      assets: _FileOnlyAssetStore(targetAssets),
      remote: connect(server(), cursorName: 'target-cursor.json'),
    );
    addTearDown(uploader.dispose);
    addTearDown(downloader.dispose);

    await uploader.synchronize();
    expect(uploader.status.phase, SyncPhase.synced);
    expect(chunks, [block, 25]);
    expect(await source.pending(), isEmpty);

    await downloader.synchronize();
    expect(downloader.status.phase, SyncPhase.synced);
    expect((await target.list()).single.notebook.recordings.single.assetId, id);
    final received = File('$targetAssets/$id');
    expect((await sha256.bind(received.openRead()).first).toString(), id);
  });
}
