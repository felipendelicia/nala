import 'dart:isolate';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/account/auth_service.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/sync/drive_remote_store.dart';
import 'package:apuntes/sync/upload_session_store.dart';
import 'package:apuntes/sync/remote_store.dart';
import '../support/fake_auth_service.dart';
import '../support/fixtures.dart';

class TestUploadSessions implements UploadSessionStore {
  final values = <String, Uri>{};
  @override
  Future<Uri?> read(String accountId, String assetId) async =>
      values['$accountId:$assetId'];
  @override
  Future<void> write(String accountId, String assetId, Uri url) async {
    values['$accountId:$assetId'] = url;
  }

  @override
  Future<void> delete(String accountId, String assetId) async {
    values.remove('$accountId:$assetId');
  }
}

Revision revision(String id) => Revision(
  id: id,
  deviceId: 'pc',
  parentId: null,
  createdAt: DateTime.utc(2026),
  notebook: fixtureNotebook(id: 'doc-$id'),
);
Map<String, Object> metadata(
  String id,
  String kind,
  Map<String, String> properties,
) => {
  'id': id,
  'name': id,
  'appProperties': {'application': 'nala-v1', 'kind': kind, ...properties},
};

void main() {
  test(
    'confirmación perdida y duplicados procesan el documento fuera de UI',
    () async {
      final base = revision('large');
      final r = Revision(
        id: base.id,
        deviceId: base.deviceId,
        parentId: base.parentId,
        createdAt: base.createdAt,
        notebook: base.notebook.copyWith(
          pages: [
            base.notebook.pages.first.copyWith(
              strokes: [
                InkStroke(
                  id: 'long',
                  tool: InkTool.pen,
                  argb: 0xff202020,
                  width: 2,
                  points: List.generate(
                    5000,
                    (i) => InkPoint(
                      x: 20 + i % 500 * 1.0,
                      y: 20 + i ~/ 500 * 1.0,
                      pressure: .5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      final payload = NotebookCodec.encodeRevision(r);
      final events = <(String, SendPort)>[];
      final receive = ReceivePort();
      final subscription = receive.listen(
        (event) => events.add(event as (String, SendPort)),
      );
      NotebookCodec.diagnostics = receive.sendPort;
      var written = false;
      final client = MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path.startsWith('/upload/')) {
          written = true;
          throw TimeoutException('ack perdido');
        }
        if (request.url.queryParameters['alt'] == 'media') {
          return http.Response.bytes(utf8.encode(payload), 200);
        }
        final q = request.url.queryParameters['q'] ?? '';
        return http.Response(
          jsonEncode({
            'files': q.contains("value='root'")
                ? [metadata('root', 'root', {})]
                : written
                ? [
                    metadata('one', 'revision', {'revisionId': r.id}),
                    metadata('two', 'revision', {'revisionId': r.id}),
                  ]
                : [],
          }),
          200,
        );
      });
      final remote = DriveRemoteStore(
        auth: FakeAuthService(),
        client: client,
        accountId: 'student',
        sessions: TestUploadSessions(),
        codecEvents: receive.sendPort,
      );
      try {
        await remote.putRevision(r);
        expect(await remote.listRevisions(), hasLength(1));
        await Future<void>.delayed(Duration.zero);
        expect(events, isNotEmpty);
        expect(
          events.every((event) => event.$2 != Isolate.current.controlPort),
          isTrue,
          reason: 'El trabajo real del codec debe quedar fuera de UI.',
        );
        expect(
          events.map((event) => event.$1),
          containsAll(['encode-revision', 'decode-revision']),
        );
      } finally {
        NotebookCodec.diagnostics = null;
        remote.close();
        await subscription.cancel();
        receive.close();
      }
    },
  );
  test(
    'listado paginado y duplicados idénticos conservan todas las revisiones',
    () async {
      final r1 = revision('r1'), r2 = revision('r2');
      final client = MockClient((request) async {
        if (request.url.queryParameters['alt'] == 'media') {
          return http.Response(
            NotebookCodec.encodeRevision(
              request.url.path.endsWith('/file-1') ? r1 : r2,
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        expect(
          request.url.queryParameters['q'],
          contains("key='application' and value='nala-v1'"),
        );
        final second = request.url.queryParameters['pageToken'] == 'next';
        return http.Response(
          jsonEncode(
            second
                ? {
                    'files': [
                      metadata('file-2', 'revision', {'revisionId': 'r2'}),
                      metadata('file-1', 'revision', {'revisionId': 'r1'}),
                    ],
                  }
                : {
                    'files': [
                      metadata('file-1', 'revision', {'revisionId': 'r1'}),
                    ],
                    'nextPageToken': 'next',
                  },
          ),
          200,
        );
      });
      final remote = DriveRemoteStore(
        auth: FakeAuthService(),
        client: client,
        accountId: 'student',
        sessions: TestUploadSessions(),
      );
      expect((await remote.listRevisions()).map((r) => r.id).toSet(), {
        'r1',
        'r2',
      });
      remote.close();
    },
  );
  test(
    'multipart con respuesta perdida se confirma por revisionId y no duplica',
    () async {
      final r = revision('immutable');
      var written = false, posts = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path.startsWith('/upload/')) {
          posts++;
          expect(
            request.headers['content-type'],
            contains('multipart/related'),
          );
          expect(request.body, contains('"revisionId":"immutable"'));
          written = true;
          throw TimeoutException('Confirmación perdida');
        }
        if (request.url.queryParameters['alt'] == 'media') {
          return http.Response(
            NotebookCodec.encodeRevision(r),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final q = request.url.queryParameters['q'] ?? '';
        return http.Response(
          jsonEncode({
            'files': q.contains("value='root'")
                ? [metadata('root', 'root', {})]
                : written
                ? [
                    metadata('file-r', 'revision', {'revisionId': r.id}),
                  ]
                : [],
          }),
          200,
        );
      });
      final remote = DriveRemoteStore(
        auth: FakeAuthService(),
        client: client,
        accountId: 'student',
        sessions: TestUploadSessions(),
      );
      await remote.putRevision(r);
      await remote.putRevision(r);
      expect(posts, 1);
      await expectLater(
        remote.putRevision(
          Revision(
            id: r.id,
            deviceId: r.deviceId,
            parentId: null,
            createdAt: r.createdAt,
            notebook: r.notebook.copyWith(title: 'Alterado'),
          ),
        ),
        throwsFormatException,
      );
      remote.close();
    },
  );
  test(
    '401 renueva una vez; revocación y Retry-After tienen estados explícitos',
    () async {
      final auth = FakeAuthService();
      var calls = 0;
      final client = MockClient(
        (_) async => ++calls == 1
            ? http.Response('', 401)
            : http.Response('{"files":[]}', 200),
      );
      final remote = DriveRemoteStore(
        auth: auth,
        client: client,
        accountId: 'student',
        sessions: TestUploadSessions(),
      );
      expect(await remote.listRevisions(), isEmpty);
      expect(auth.refreshes, 1);
      remote.close();
      final revoked = DriveRemoteStore(
        auth: auth,
        client: MockClient((_) async => http.Response('', 401)),
        accountId: 'student',
        sessions: TestUploadSessions(),
      );
      await expectLater(
        revoked.listRevisions(),
        throwsA(isA<RemoteSignInRequired>()),
      );
      revoked.close();
      final limited = DriveRemoteStore(
        auth: auth,
        client: MockClient(
          (_) async => http.Response('', 429, headers: {'retry-after': '120'}),
        ),
        accountId: 'student',
        sessions: TestUploadSessions(),
      );
      await expectLater(
        limited.listRevisions(),
        throwsA(
          isA<RemoteRetryLater>().having(
            (e) => e.delay,
            'delay',
            const Duration(seconds: 120),
          ),
        ),
      );
      limited.close();
    },
  );
  test(
    'recurso reanuda tras 308, consulta rango y elimina sesión al confirmar',
    () async {
      final bytes = Uint8List(600000)..fillRange(0, 600000, 7);
      final id = sha256.convert(bytes).toString();
      final sessions = TestUploadSessions();
      var received = 0, lost = false, starts = 0;
      final ranges = <String>[];
      final client = MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path.startsWith('/upload/')) {
          starts++;
          return http.Response(
            '',
            200,
            headers: {
              'location':
                  'https://www.googleapis.com/upload/drive/v3/files?upload_id=fixture',
            },
          );
        }
        if (request.method == 'PUT') {
          final range = request.headers['content-range']!;
          ranges.add(range);
          if (range.startsWith('bytes */')) {
            return http.Response(
              '',
              308,
              headers: received == 0
                  ? {}
                  : {'range': 'bytes=0-${received - 1}'},
            );
          }
          final match = RegExp(r'bytes (\d+)-(\d+)/').firstMatch(range)!;
          expect(int.parse(match[1]!), received);
          received = int.parse(match[2]!) + 1;
          if (!lost) {
            lost = true;
            throw TimeoutException('Se perdió la respuesta');
          }
          if (received < bytes.length) {
            return http.Response(
              '',
              308,
              headers: {'range': 'bytes=0-${received - 1}'},
            );
          }
          return http.Response(
            jsonEncode({
              'id': 'asset-file',
              'md5Checksum': md5.convert(bytes).toString(),
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'files':
                (request.url.queryParameters['q'] ?? '').contains(
                  "value='root'",
                )
                ? [metadata('root', 'root', {})]
                : [],
          }),
          200,
        );
      });
      final remote = DriveRemoteStore(
        auth: FakeAuthService(),
        client: client,
        accountId: 'student',
        sessions: sessions,
      );
      await expectLater(
        remote.putAsset(id, bytes),
        throwsA(isA<TimeoutException>()),
      );
      expect(await sessions.read('student', id), isNotNull);
      await remote.putAsset(id, bytes);
      expect(received, bytes.length);
      expect(starts, 1);
      expect(ranges, contains('bytes */600000'));
      expect(await sessions.read('student', id), isNull);
      remote.close();
    },
  );
  test(
    'sesión expirada reinicia y una cuenta ajena no usa el cliente anterior',
    () async {
      final bytes = Uint8List.fromList('fixture asset'.codeUnits);
      final id = sha256.convert(bytes).toString();
      final sessions = TestUploadSessions();
      await sessions.write(
        'student',
        id,
        Uri.parse(
          'https://www.googleapis.com/upload/drive/v3/files?upload_id=expired',
        ),
      );
      var starts = 0;
      final auth = FakeAuthService();
      final client = MockClient((request) async {
        if (request.url.queryParameters['upload_id'] == 'expired') {
          return http.Response('', 404);
        }
        if (request.method == 'POST') {
          starts++;
          return http.Response(
            '',
            200,
            headers: {
              'location':
                  'https://www.googleapis.com/upload/drive/v3/files?upload_id=fresh',
            },
          );
        }
        if (request.method == 'PUT') {
          return http.Response(
            jsonEncode({
              'id': 'asset-file',
              'md5Checksum': md5.convert(bytes).toString(),
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'files':
                (request.url.queryParameters['q'] ?? '').contains(
                  "value='root'",
                )
                ? [metadata('root', 'root', {})]
                : [],
          }),
          200,
        );
      });
      final remote = DriveRemoteStore(
        auth: auth,
        client: client,
        accountId: 'student',
        sessions: sessions,
      );
      await remote.putAsset(id, bytes);
      expect(starts, 1);
      auth.current = const GoogleAccount('other', 'other@example.invalid');
      await expectLater(
        remote.listRevisions(),
        throwsA(isA<RemoteSignInRequired>()),
      );
      remote.close();
    },
  );
}
