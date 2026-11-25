import 'dart:convert';
import 'dart:io';
import 'package:apuntes/account/cloud_controller.dart';
import 'package:apuntes/account/token_store.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/folders.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/sync/sync_state.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import '../support/fixtures.dart';

const url = 'https://notes.example.invalid';
const token = 'test-device-secret';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late _Server server;
  late _Keyring keyring;
  late CloudController cloud;

  Future<CloudController> open() => CloudController.open(
    dir.path,
    tokenStore: keyring,
    clientFactory: () => MockClient(server.handle),
    autoStart: false,
  );

  Future<void> connect({bool remember = true}) async {
    await cloud.probe(url, token);
    await cloud.confirmConnection(remember: remember);
    expect(cloud.connected, isTrue);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nala-server-account-');
    server = _Server();
    keyring = _Keyring();
  });
  tearDown(() async {
    await cloud.close();
    await dir.delete(recursive: true);
  });

  test(
    'la primera migración preserva las revisiones y los borrados locales',
    () async {
      cloud = await open();
      final first = Revision(
        id: 'original',
        parentId: null,
        deviceId: 'tablet',
        createdAt: DateTime.utc(2026, 10, 6),
        notebook: fixtureNotebook(),
      );
      final edited = Revision(
        id: 'edited',
        parentId: first.id,
        deviceId: 'tablet',
        createdAt: DateTime.utc(2026, 10, 6),
        notebook: first.notebook.copyWith(title: 'Última versión'),
      );
      final repository = cloud.services.repository;
      await repository.acceptRemote(first);
      await repository.acceptRemote(edited);
      await (repository as FolderRepository).mergeFolders([
        NoteFolder(id: 'deleted', name: 'Vieja', deleted: true),
      ]);
      expect(await cloud.services.repository.pending(), isEmpty);

      await cloud.probe(url, token);
      expect(cloud.pendingConnection?.requiresUpload, isTrue);
      await cloud.synchronize();
      expect(server.methods, ['GET /v1/identity']);
      expect(await cloud.services.repository.pending(), isEmpty);

      await cloud.confirmConnection();
      expect(cloud.services.root, dir.path);
      expect(
        (await cloud.services.repository.pending()).map(
          (revision) => revision.id,
        ),
        ['original', 'edited'],
      );
      await cloud.synchronize();
      expect(server.revisions.keys, ['original', 'edited']);
      expect(server.folders['deleted']?['deleted'], isTrue);
      expect(cloud.status.phase, SyncPhase.synced);
      expect(await cloud.services.repository.pending(), isEmpty);
    },
  );

  test(
    'una identidad restaurada exige confirmar de nuevo antes de enviar',
    () async {
      cloud = await open();
      await cloud.services.repository.acceptRemote(
        Revision(
          id: 'old-notebook',
          parentId: null,
          deviceId: 'tablet',
          createdAt: DateTime.utc(2026, 10, 6),
          notebook: fixtureNotebook(),
        ),
      );
      await connect();
      await cloud.synchronize();
      await cloud.close();

      server.id = 'fresh-generation';
      server.revisions.clear();
      server.methods.clear();
      cloud = await open();
      await cloud.synchronize();
      expect(cloud.status.phase, SyncPhase.needsSignIn);
      expect(server.methods, everyElement(startsWith('GET ')));
      expect(
        (await cloud.services.repository.list()).single.notebook.id,
        'doc-1',
      );

      await cloud.probe(url, token);
      expect(cloud.pendingConnection?.requiresUpload, isTrue);
      await cloud.cancelConnection();
      await cloud.confirmConnection();
      await cloud.synchronize();
      expect(server.revisions, isEmpty);
      expect(cloud.connected, isFalse);

      await connect();
      await cloud.synchronize();
      expect(server.revisions.keys, ['old-notebook']);
    },
  );

  test(
    'una biblioteca vacía conecta y conserva lo agregado antes de confirmar',
    () async {
      cloud = await open();
      await cloud.probe(url, token);
      expect(cloud.pendingConnection?.requiresUpload, isFalse);

      await cloud.services.repository.acceptRemote(
        Revision(
          id: 'added-after-probe',
          parentId: null,
          deviceId: 'tablet',
          createdAt: DateTime.utc(2026, 10, 6),
          notebook: fixtureNotebook(),
        ),
      );
      await cloud.confirmConnection();
      await cloud.synchronize();
      expect(server.revisions.keys, ['added-after-probe']);
    },
  );

  test(
    'un destino distinto vuelve a descargar aunque repita la identidad',
    () async {
      cloud = await open();
      await cloud.services.repository.acceptRemote(
        Revision(
          id: 'original-revision',
          parentId: null,
          deviceId: 'tablet',
          createdAt: DateTime.utc(2026, 10, 6),
          notebook: fixtureNotebook(),
        ),
      );
      await connect();
      await cloud.synchronize();
      final imported = Revision(
        id: 'other-destination-revision',
        parentId: null,
        deviceId: 'tablet',
        createdAt: DateTime.utc(2026, 10, 6),
        notebook: fixtureNotebook(id: 'other-destination-notebook'),
      );
      server.revisions
        ..clear()
        ..[imported.id] = jsonDecode(NotebookCodec.encodeRevision(imported));

      await cloud.probe('https://another-server.example.invalid', token);
      await cloud.confirmConnection();
      await cloud.synchronize();
      expect(
        (await cloud.services.repository.list()).map(
          (entry) => entry.notebook.id,
        ),
        unorderedEquals(['doc-1', 'other-destination-notebook']),
      );
    },
  );

  test(
    'cambiar la URL guardada no reutiliza la credencial del destino anterior',
    () async {
      cloud = await open();
      await connect();
      await cloud.close();

      final file = File(p.join(dir.path, 'server-connection.json'));
      final config =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      config['url'] = 'https://unverified.example.invalid';
      await file.writeAsString(jsonEncode(config));

      cloud = await open();
      expect(cloud.connected, isFalse);
      expect(cloud.status.phase, SyncPhase.needsSignIn);
      expect(keyring.values.values, [token]);
    },
  );

  test('una credencial revocada mantiene los cambios pendientes', () async {
    cloud = await open();
    await connect();
    server.revoked = true;
    await cloud.services.repository.commit(
      Revision(
        id: 'offline',
        parentId: null,
        deviceId: 'tablet',
        createdAt: DateTime.utc(2026, 10, 6),
        notebook: fixtureNotebook(),
      ),
    );
    await cloud.synchronize();
    expect(cloud.status.phase, SyncPhase.needsSignIn);
    expect(server.revisions, isEmpty);
    expect((await cloud.services.repository.pending()).single.id, 'offline');

    await cloud.probe(url, token);
    expect(cloud.pendingConnection, isNull);
    expect(cloud.status.phase, SyncPhase.needsSignIn);
  });

  test(
    'selecciona la biblioteca anterior y permite abrir otras copias locales',
    () async {
      final partitionA = sha256.convert(utf8.encode('account-a')).toString();
      final partitionB = sha256.convert(utf8.encode('account-b')).toString();
      final rootA = p.join(dir.path, 'accounts', partitionA);
      final rootB = p.join(dir.path, 'accounts', partitionB);
      for (final (root, name) in [(rootA, 'A'), (rootB, 'B')]) {
        final local = await AppServices.open(root);
        await local.repository.acceptRemote(
          Revision(
            id: 'revision-$name',
            parentId: null,
            deviceId: 'tablet',
            createdAt: DateTime.utc(2026, 10, 6),
            notebook: fixtureNotebook(id: name),
          ),
        );
        await local.close();
      }
      await File(p.join(dir.path, 'active-account.json')).writeAsString(
        '{"id":"account-a","email":"anterior@example.invalid","connected":true}',
      );
      cloud = await open();
      expect(cloud.services.root, rootA);
      expect((await cloud.services.repository.list()).single.notebook.id, 'A');

      await cloud.selectCatalog(
        cloud.catalogs.singleWhere((catalog) => catalog.root == rootB),
      );
      expect((await cloud.services.repository.list()).single.notebook.id, 'B');
      await connect();
      await cloud.synchronize();
      expect(server.revisions.keys, ['revision-B']);
      await cloud.close();

      cloud = await open();
      expect(cloud.services.root, rootB);
      expect(cloud.connected, isTrue);
      await cloud.selectCatalog(
        cloud.catalogs.singleWhere((catalog) => catalog.root == rootA),
      );
      expect((await cloud.services.repository.list()).single.notebook.id, 'A');
      expect(cloud.connected, isFalse);
    },
  );

  test(
    'la sesión continúa sin llavero y la credencial no se escribe en el catálogo',
    () async {
      keyring.unavailable = true;
      cloud = await open();
      await connect();
      await cloud.synchronize();
      expect(cloud.status.phase, SyncPhase.synced);
      final config = await File(
        p.join(dir.path, 'server-connection.json'),
      ).readAsString();
      expect(jsonDecode(config), containsPair('url', url));
      expect(config, isNot(contains(token)));
      await cloud.close();

      keyring.unavailable = false;
      cloud = await open();
      expect(keyring.values, isEmpty);
      expect(cloud.connected, isFalse);
      expect(cloud.status.phase, SyncPhase.needsSignIn);
    },
  );

  test(
    'desconectar persiste si el llavero no puede borrar la credencial',
    () async {
      cloud = await open();
      await connect();
      keyring.unavailable = true;
      await cloud.disconnect();
      expect(cloud.connected, isFalse);
      expect(cloud.message, isNotNull);
      await cloud.close();

      keyring.unavailable = false;
      cloud = await open();
      expect(keyring.values.values, [token]);
      expect(cloud.connected, isFalse);
      expect(cloud.status.phase, SyncPhase.localOnly);
    },
  );
}

http.Response _json(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

class _Server {
  String id = 'original-generation';
  bool revoked = false;
  final methods = <String>[];
  final revisions = <String, Object?>{};
  final folders = <String, Map<String, dynamic>>{};

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    methods.add('${request.method} $path');
    if (revoked || request.headers['authorization'] != 'Bearer $token') {
      return http.Response('{"error":"unauthorized"}', 401);
    }
    if (path == '/v1/identity') {
      return http.Response(jsonEncode({'id': id}), 200);
    }
    if (request.headers['x-nala-server'] != id) {
      return http.Response('{"error":"server_changed"}', 409);
    }
    if (path == '/v1/folders' && request.method == 'GET') {
      return _json({'items': folders.values.toList()});
    }
    if (path == '/v1/folders' && request.method == 'PUT') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final items = (body['items'] as List?) ?? [body];
      for (final folder in items.cast<Map<String, dynamic>>()) {
        folders[folder['id'] as String] = folder;
      }
      return _json({});
    }
    if (path == '/v1/revisions' && request.method == 'GET') {
      final after = int.parse(request.url.queryParameters['after']!);
      return _json({
        'items': revisions.values.skip(after).toList(),
        'next': revisions.length,
        'more': false,
      });
    }
    if (path == '/v1/revisions' && request.method == 'PUT') {
      final revision = NotebookCodec.decodeRevision(request.body);
      revisions[revision.id] = jsonDecode(request.body);
      return http.Response('{}', 200);
    }
    return http.Response('{"error":"not_found"}', 404);
  }
}

class _Keyring implements TokenStore {
  bool unavailable = false;
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async {
    if (unavailable) throw StateError('No keyring');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (unavailable) throw StateError('No keyring');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (unavailable) throw StateError('No keyring');
    values.remove(key);
  }
}
