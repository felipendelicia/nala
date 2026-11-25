import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/account/cloud_controller.dart';
import 'package:apuntes/account/token_store.dart';
import 'package:apuntes/document/folders.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/page_comment.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/sync/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/pdf_fixtures.dart';

class _NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _MemoryTokens implements TokenStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

Future<String> _command(Map<String, String> env, List<String> args) async {
  final result = await Process.run(
    'python3',
    ['-m', 'nala_server', ...args],
    workingDirectory: 'server',
    environment: env,
  );
  if (result.exitCode != 0) {
    throw StateError('Servidor ${args.first}: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

Future<void> _waitForServer(int port) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    try {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      socket.destroy();
      return;
    } on SocketException {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }
  throw StateError('No inició el servidor local de prueba.');
}

Revision _revision(String id, String? parent, Notebook book, String device) =>
    Revision(
      id: id,
      deviceId: device,
      parentId: parent,
      createdAt: DateTime.utc(2026, 11, 24),
      notebook: book,
    );

void main() {
  _NetworkTestBinding();

  test(
    'sincroniza adjuntos, conflictos y eliminaciones entre bibliotecas reales',
    () async {
      final directory = await Directory.systemTemp.createTemp('nala-e2e-');
      addTearDown(() => directory.delete(recursive: true));

      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final env = {
        'NALA_BIND': '127.0.0.1',
        'NALA_PORT': '$port',
        'NALA_DATA_DIR': '${directory.path}/server',
      };
      final tabletToken = await _command(env, ['token-create', 'tablet']);
      final pcToken = await _command(env, ['token-create', 'pc']);
      Future<Future<void> Function()> startServer() async {
        final server = await Process.start(
          'python3',
          ['-m', 'nala_server', 'serve'],
          workingDirectory: 'server',
          environment: env,
        );
        final errors = server.stderr.drain<void>();
        final messages = server.stdout.drain<void>();
        var stopped = false;
        Future<void> stop() async {
          if (stopped) return;
          stopped = true;
          server.kill();
          await server.exitCode;
          await Future.wait([errors, messages]);
        }

        addTearDown(stop);
        await _waitForServer(port);
        return stop;
      }

      final stopServer = await startServer();

      final tabletTokens = _MemoryTokens(), pcTokens = _MemoryTokens();
      Future<CloudController> open(String device, _MemoryTokens tokens) =>
          CloudController.open(
            '${directory.path}/$device',
            tokenStore: tokens,
            autoStart: false,
            allowInsecureLoopback: true,
          );
      var tablet = await open('tablet', tabletTokens);
      final pc = await open('pc', pcTokens);
      addTearDown(() => tablet.close());
      addTearDown(pc.close);
      final tabletDb = tablet.services.repository as SqliteNotebookRepository;
      final pcDb = pc.services.repository as SqliteNotebookRepository;

      await tabletDb.saveFolder(NoteFolder(id: 'materia', name: 'Análisis'));
      final pdf = await makeFixturePdf();
      final audio = Uint8List(4 * 1024 * 1024 + 64);
      audio.setRange(0, 12, 'RIFFxxxxWAVE'.codeUnits);
      audio[audio.length - 1] = 23;
      final pdfId = await tablet.services.assets.put(pdf);
      final voiceId = await tablet.services.assets.put(audio);
      final source = fixtureNotebook();
      final notebook = source.copyWith(
        folderId: 'materia',
        pages: [
          source.pages.first.copyWith(
            background: PageBackground.pdf(pdfId, 1),
            comments: [
              PageComment(
                id: 'nota-de-voz',
                x: 50,
                y: 100,
                text: 'Repasar',
                createdAt: DateTime.utc(2026, 11, 24),
                audioAssetId: voiceId,
                audioDurationMs: 1200,
              ),
            ],
          ),
        ],
      );
      await tabletDb.commit(_revision('origen', null, notebook, 'tablet'));
      await tabletDb.markUploaded('origen');
      expect(await tabletDb.pending(), isEmpty);

      final url = 'http://127.0.0.1:$port';
      await tablet.probe(url, tabletToken);
      expect(tablet.pendingConnection?.requiresUpload, isTrue);
      await pc.probe(url, pcToken);
      await pc.confirmConnection();
      await pc.synchronize();
      expect(pc.status.phase, SyncPhase.synced);
      expect(await pcDb.list(), isEmpty);

      await tablet.confirmConnection();
      await tablet.synchronize();
      expect(tablet.status.phase, SyncPhase.synced);
      await pc.synchronize();
      expect(pc.status.phase, SyncPhase.synced);
      expect((await pcDb.list()).single.headId, 'origen');
      expect(await pcDb.isDeleted(notebook.id), isFalse);
      expect((await pcDb.listFolders()).single.name, 'Análisis');
      expect(await pc.services.assets.read(pdfId), pdf);
      expect(await pc.services.assets.read(voiceId), audio);

      await stopServer();
      await tabletDb.commit(
        _revision(
          'tablet-offline',
          'origen',
          notebook.copyWith(title: 'Tablet'),
          'tablet',
        ),
      );
      await pcDb.commit(
        _revision('pc-offline', 'origen', notebook.copyWith(title: 'PC'), 'pc'),
      );
      await tablet.synchronize();
      expect(tablet.status.phase, SyncPhase.error);
      await tablet.close();
      await startServer();
      tablet = await open('tablet', tabletTokens);
      expect(tablet.connected, isTrue);
      expect(
        (await tablet.services.repository.pending()).single.id,
        'tablet-offline',
      );
      await tablet.synchronize();
      await pc.synchronize();
      await tablet.synchronize();
      for (final controller in [tablet, pc]) {
        expect(controller.status.phase, SyncPhase.synced);
        final entries = await controller.services.repository.list();
        expect(
          entries.map((entry) => entry.headId),
          unorderedEquals(['tablet-offline', 'pc-offline']),
        );
        expect(entries.every((entry) => entry.isConflict), isTrue);
        expect(await controller.services.repository.pending(), isEmpty);
      }

      final deletingDb = tablet.services.repository;
      final deletingLibrary = tablet.services.library;
      await deletingLibrary.refresh();
      final selected = deletingLibrary.entries.firstWhere(
        (entry) => entry.headId == 'tablet-offline',
      );
      await deletingDb.commit(
        _revision(
          'unsynced-before-delete',
          selected.headId,
          notebook.copyWith(title: 'Edición aún no enviada'),
          'tablet',
        ),
      );
      await deletingLibrary.refresh();
      await deletingLibrary.deleteNotebook(
        deletingLibrary.entries.firstWhere(
          (entry) => entry.headId == 'unsynced-before-delete',
        ),
      );
      expect(await deletingDb.list(), isEmpty);
      expect((await deletingDb.pending()).map((r) => r.notebook.title), [
        'Edición aún no enviada',
        'Edición aún no enviada',
      ]);
      await tablet.synchronize();
      expect(tablet.status.phase, SyncPhase.synced);
      expect(await pcDb.list(), hasLength(2));

      await pcDb.commit(
        _revision(
          'late-pc-edit',
          'pc-offline',
          notebook.copyWith(title: 'Edición anterior a recibir el borrado'),
          'pc',
        ),
      );
      await pc.synchronize();
      await tablet.synchronize();
      for (final db in [deletingDb, pcDb]) {
        expect(await db.list(), isEmpty);
        expect(await db.isDeleted(notebook.id), isTrue);
        expect(await db.load(notebook.id, headId: 'late-pc-edit'), isNull);
        final retained = await db.history(notebook.id);
        expect(retained.map((r) => r.id), contains('late-pc-edit'));
        expect(
          retained.where((r) => r.deleted).single.parentId,
          'unsynced-before-delete',
        );
      }
      await tablet.close();
      tablet = await open('tablet', tabletTokens);
      expect(tablet.services.library.entries, isEmpty);
      expect(await tablet.services.repository.pending(), isEmpty);

      await _command(env, ['token-revoke', 'pc']);
      await pc.synchronize();
      expect(pc.status.phase, SyncPhase.needsSignIn);
      expect(await pcDb.list(), isEmpty);
    },
  );
}
