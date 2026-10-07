import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:apuntes/sync/sync_state.dart';
import '../support/fake_remote_store.dart';
import '../support/study_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'study media and cards survive SQLite reopen and a verified cloud round-trip',
    () async {
      final dir = await Directory.systemTemp.createTemp('nala-study-sync-');
      final localAssets = FileAssetStore('${dir.path}/local-assets');
      final otherAssets = FileAssetStore('${dir.path}/other-assets');
      final database = '${dir.path}/local.db';
      var local = await SqliteNotebookRepository.open(database);
      final other = await SqliteNotebookRepository.open('${dir.path}/other.db');
      final remote = FakeRemoteStore();
      SyncEngine? localSync, otherSync;
      try {
        final media = <String, Uint8List>{};
        for (final name in ['cover', 'recording', 'image', 'background']) {
          final bytes = Uint8List.fromList('synthetic $name'.codeUnits);
          media[await localAssets.put(bytes)] = bytes;
        }
        final ids = media.keys.toList();
        final map = studyPayload();
        map['coverAssetId'] = ids[0];
        map['recordings'][0]['assetId'] = ids[1];
        map['pages'][0]['objects'][1]['assetId'] = ids[2];
        map['pages'][0]['background'] = {'kind': 'image', 'assetId': ids[3]};
        final book = NotebookCodec.decode(jsonEncode(map));
        await local.commit(
          Revision(
            id: 'revision-media',
            deviceId: 'tablet',
            parentId: null,
            createdAt: DateTime.utc(2026, 10, 7),
            notebook: book,
          ),
        );
        await local.close();
        local = await SqliteNotebookRepository.open(database);
        expect(
          (await local.load('doc-1'))!.studyCards.single.back,
          'Un valor propio',
        );
        localSync = SyncEngine(
          repository: local,
          assets: localAssets,
          remote: remote,
        );
        otherSync = SyncEngine(
          repository: other,
          assets: otherAssets,
          remote: remote,
        );
        await localSync.synchronize();
        expect(localSync.status.phase, SyncPhase.synced);
        remote.assets[ids[0]] = Uint8List.fromList('bad cover'.codeUnits);
        await otherSync.synchronize();
        expect(await other.list(), isEmpty);
        expect(otherSync.status.phase, SyncPhase.error);
        remote.assets[ids[0]] = media[ids[0]]!;
        await otherSync.synchronize();
        final received = (await other.load('doc-1'))!;
        expect(received.coverAssetId, ids[0]);
        expect(received.recordings.single.durationMs, 1200);
        expect(received.pages.single.objects.last.assetId, ids[2]);
        expect(received.pages.single.background.isImage, isTrue);
        expect(received.studyCards.single.front, '¿Qué es λ?');
        expect(received.pages.single.strokes.single.audioOffsetMs, 400);
        for (final entry in media.entries) {
          expect(await otherAssets.read(entry.key), entry.value);
        }
      } finally {
        localSync?.dispose();
        otherSync?.dispose();
        await local.close();
        await other.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
