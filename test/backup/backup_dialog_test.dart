import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/backup/backup_dialog.dart';
import 'package:apuntes/backup/backup_files.dart';
import 'package:apuntes/backup/backup_service.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';

class _Files implements BackupFiles {
  _Files(this.bytes);
  final Uint8List bytes;
  @override
  Future<SelectedBackup?> open() async =>
      SelectedBackup(bytes: bytes, name: 'Class.nala.zip');
  @override
  Future<bool> save(Uint8List bytes, {required String name}) async => false;
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget);
}

void main() {
  testWidgets(
    'preview explains recovery and selected preferences restore with existing notes preserved',
    (tester) async {
      late Directory source, target;
      late SqliteNotebookRepository sourceRepo, targetRepo;
      late BackupService importer;
      late Uint8List backup;
      final now = DateTime.utc(2026, 10, 7);
      await tester.runAsync(() async {
        source = await Directory.systemTemp.createTemp(
          'nala-backup-ui-source-',
        );
        target = await Directory.systemTemp.createTemp(
          'nala-backup-ui-target-',
        );
        sourceRepo = await SqliteNotebookRepository.open(
          '${source.path}/notes.db',
        );
        targetRepo = await SqliteNotebookRepository.open(
          '${target.path}/notes.db',
        );
        for (final pair in [
          (sourceRepo, 'source', 'Class'),
          (targetRepo, 'existing', 'Existing'),
        ]) {
          await pair.$1.commit(
            Revision(
              id: '${pair.$2}-revision',
              deviceId: 'fixture',
              parentId: null,
              createdAt: now,
              notebook: Notebook.blank(
                id: pair.$2,
                pageId: '${pair.$2}-page',
                title: pair.$3,
                pattern: PaperPattern.blank,
                now: now,
              ),
            ),
          );
        }
        await File(
          '${source.path}/appearance.json',
        ).writeAsString(jsonEncode({'theme': 'dark'}));
        await File(
          '${target.path}/appearance.json',
        ).writeAsString(jsonEncode({'theme': 'light'}));
        backup = await BackupService(
          root: source.path,
          repository: sourceRepo,
          assets: FileAssetStore('${source.path}/assets'),
          deviceId: 'source',
        ).export();
        importer = BackupService(
          root: target.path,
          repository: targetRepo,
          assets: FileAssetStore('${target.path}/assets'),
          deviceId: 'target',
        );
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          await sourceRepo.close();
          await targetRepo.close();
          await source.delete(recursive: true);
          await target.delete(recursive: true);
        });
      });
      BackupRestoreResult? restored;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BackupDialog(
              service: importer,
              files: _Files(backup),
              onRestored: (result) async {
                restored = result;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir backup'));
      await _waitFor(tester, find.text('Recuperar copias'));
      expect(
        find.textContaining('1 cuadernos · 1 versiones actuales'),
        findsOneWidget,
      );
      expect(
        find.textContaining('conserva los apuntes actuales'),
        findsOneWidget,
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Recuperar copias'));
      await _waitFor(tester, find.text('Abrir carpeta recuperada'));
      expect(restored!.preferencesRestored, isTrue);
      await tester.runAsync(() async {
        final entries = await targetRepo.list();
        expect(entries.length, 2);
        expect(await targetRepo.load('existing'), isNotNull);
        expect(
          entries.any(
            (e) => e.notebook.id != 'source' && e.notebook.title == 'Class',
          ),
          isTrue,
        );
        expect(
          jsonDecode(
            await File('${target.path}/appearance.json').readAsString(),
          ),
          {'theme': 'dark'},
        );
        expect(
          jsonDecode(
            await File(
              '${target.path}/recovery-preferences/${restored!.recoveryFolderId}/appearance.json',
            ).readAsString(),
          ),
          {'theme': 'light'},
        );
      });
      expect(tester.takeException(), isNull);
    },
  );
}
