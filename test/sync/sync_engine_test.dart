import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/folders.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/page_comment.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:apuntes/sync/sync_state.dart';
import 'package:apuntes/editor/editor_controller.dart';
import '../support/fake_remote_store.dart';
import '../support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SqliteNotebookRepository tablet, pc;
  late FileAssetStore tabletAssets, pcAssets;
  late FakeRemoteStore remote;
  late SyncEngine tabletSync, pcSync;
  Revision revision(
    String id,
    String? parent,
    Notebook note, {
    String device = 'tablet',
  }) => Revision(
    id: id,
    parentId: parent,
    deviceId: device,
    createdAt: DateTime.utc(2026, 10, 6),
    notebook: note,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nala-sync-');
    tablet = await SqliteNotebookRepository.open('${directory.path}/tablet.db');
    pc = await SqliteNotebookRepository.open('${directory.path}/pc.db');
    tabletAssets = FileAssetStore('${directory.path}/tablet-assets');
    pcAssets = FileAssetStore('${directory.path}/pc-assets');
    remote = FakeRemoteStore();
    tabletSync = SyncEngine(
      repository: tablet,
      assets: tabletAssets,
      remote: remote,
    );
    pcSync = SyncEngine(repository: pc, assets: pcAssets, remote: remote);
  });
  tearDown(() async {
    tabletSync.dispose();
    pcSync.dispose();
    await tablet.close();
    await pc.close();
    await directory.delete(recursive: true);
  });
  test(
    'dos clientes offline conservan ambas ramas y reintentan una respuesta perdida',
    () async {
      await tablet.commit(revision('base', null, fixtureNotebook()));
      await tabletSync.synchronize();
      await pcSync.synchronize();
      await tablet.commit(
        revision(
          'tablet-edit',
          'base',
          fixtureNotebook().copyWith(title: 'Cambio tablet'),
        ),
      );
      await pc.commit(
        revision(
          'pc-edit',
          'base',
          fixtureNotebook().copyWith(title: 'Cambio PC'),
          device: 'pc',
        ),
      );
      remote.loseAcknowledgement = true;
      await tabletSync.synchronize();
      expect(await tablet.pending(), hasLength(1));
      expect(tabletSync.status.phase, SyncPhase.error);
      await pcSync.synchronize();
      await tabletSync.synchronize();
      await pcSync.synchronize();
      expect((await tablet.list()).map((e) => e.headId).toSet(), {
        'tablet-edit',
        'pc-edit',
      });
      expect((await pc.list()).map((e) => e.headId).toSet(), {
        'tablet-edit',
        'pc-edit',
      });
      expect(await tablet.pending(), isEmpty);
      expect(remote.revisions, hasLength(3));
      await tabletSync.synchronize();
      expect(await tablet.list(), hasLength(2));
      expect(
        (await tablet.load('doc-1', headId: 'tablet-edit'))!.title,
        'Cambio tablet',
      );
    },
  );
  test(
    'PDF, voz y jerarquía llegan antes de hacer visible el cuaderno',
    () async {
      final pdfBytes = Uint8List.fromList('%PDF-1.7 fixture'.codeUnits);
      final voiceBytes = Uint8List.fromList(
        'RIFFxxxxWAVEvoice fixture'.codeUnits,
      );
      final pdfId = await tabletAssets.put(pdfBytes),
          voiceId = await tabletAssets.put(voiceBytes);
      final university = NoteFolder(
        id: 'university',
        name: 'Universidad',
        updatedAt: DateTime.utc(2026),
      );
      final subject = NoteFolder(
        id: 'subject',
        name: 'Álgebra',
        parentId: university.id,
        updatedAt: DateTime.utc(2026),
      );
      await tablet.saveFolder(university);
      await tablet.saveFolder(subject);
      final note = fixtureNotebook().copyWith(
        folderId: subject.id,
        pages: [
          fixtureNotebook().pages.first.copyWith(
            background: PageBackground.pdf(pdfId, 1),
            comments: [
              PageComment(
                id: 'voice',
                x: 50,
                y: 100,
                text: 'Repasar',
                createdAt: DateTime.utc(2026),
                audioAssetId: voiceId,
                audioDurationMs: 1200,
              ),
            ],
          ),
        ],
      );
      await tablet.commit(revision('with-assets', null, note));
      await tabletSync.synchronize();
      remote.assets[voiceId] = Uint8List.fromList('dañado'.codeUnits);
      await pcSync.synchronize();
      expect(await pc.list(), isEmpty);
      expect(pcSync.status.phase, SyncPhase.error);
      remote.assets[voiceId] = voiceBytes;
      await pcSync.synchronize();
      expect((await pc.list()).single.notebook.folderId, subject.id);
      expect((await pc.listFolders()).map((f) => f.name).toSet(), {
        'Universidad',
        'Álgebra',
      });
      expect(await pcAssets.read(pdfId), pdfBytes);
      expect(await pcAssets.read(voiceId), voiceBytes);
      expect(await pc.pending(), isEmpty);
      await expectLater(tablet.deleteFolder('subject'), throwsStateError);
    },
  );
  test(
    'una descarga concurrente no reemplaza la edición en memoria y no se solapan sincronizaciones',
    () async {
      await tablet.commit(revision('base', null, fixtureNotebook()));
      await tabletSync.synchronize();
      await pcSync.synchronize();
      remote.revisions['remote-edit'] = revision(
        'remote-edit',
        'base',
        fixtureNotebook().copyWith(title: 'Remoto'),
      );
      remote.listingGate = Completer<void>();
      final before = remote.listingCalls;
      final first = pcSync.synchronize(), second = pcSync.synchronize();
      final controller = EditorController(
        notebook: fixtureNotebook(),
        headId: 'base',
        repository: pc,
        deviceId: 'pc',
        newId: () => 'local-edit',
        now: () => DateTime.utc(2026),
      );
      addTearDown(controller.dispose);
      await controller.apply((book) => book.copyWith(title: 'PC offline'));
      expect(remote.listingCalls, before + 1);
      remote.listingGate!.complete();
      await first;
      await second;
      expect(controller.notebook.title, 'PC offline');
      expect((await pc.list()).map((e) => e.headId).toSet(), {
        'local-edit',
        'remote-edit',
      });
      expect(remote.revisions['local-edit']!.notebook.title, 'PC offline');
    },
  );
  test('hijo recibido antes del padre no genera un conflicto falso', () async {
    remote.revisions['child'] = revision(
      'child',
      'parent',
      fixtureNotebook().copyWith(title: 'Hijo'),
    );
    remote.revisions['parent'] = revision('parent', null, fixtureNotebook());
    await tabletSync.synchronize();
    expect((await tablet.list()).single.headId, 'child');
    expect((await tablet.list()).single.isConflict, isFalse);
  });
  test(
    'movimientos cruzados convergen sin ciclos y las carpetas borradas no resucitan',
    () async {
      final a = NoteFolder(
        id: 'a',
        name: 'Álgebra',
        updatedAt: DateTime.utc(2026),
      );
      final b = NoteFolder(
        id: 'b',
        name: 'Física',
        updatedAt: DateTime.utc(2026),
      );
      await tablet.saveFolder(a);
      await tablet.saveFolder(b);
      await tabletSync.synchronize();
      await pcSync.synchronize();
      await tablet.saveFolder(
        a.copyWith(parentId: 'b', updatedAt: DateTime.utc(2026, 10, 5)),
      );
      await pc.saveFolder(
        b.copyWith(parentId: 'a', updatedAt: DateTime.utc(2026, 10, 5)),
      );
      await tabletSync.synchronize();
      await pcSync.synchronize();
      await tabletSync.synchronize();
      expect(
        {for (final f in await tablet.listFolders()) f.id: f.parentId},
        {'a': null, 'b': 'a'},
      );
      expect(
        {for (final f in await pc.listFolders()) f.id: f.parentId},
        {'a': null, 'b': 'a'},
      );
      await tablet.saveFolder(
        NoteFolder(id: 'empty', name: 'Vacía', updatedAt: DateTime.utc(2026)),
      );
      await tabletSync.synchronize();
      await pcSync.synchronize();
      await tablet.deleteFolder('empty');
      await tabletSync.synchronize();
      await pcSync.synchronize();
      await tabletSync.synchronize();
      expect((await pc.listFolders()).any((f) => f.id == 'empty'), isFalse);
      expect(
        (await pc.listFolders(
          includeDeleted: true,
        )).singleWhere((f) => f.id == 'empty').deleted,
        isTrue,
      );
    },
  );
}
