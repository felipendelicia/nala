import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/editor/editor_controller.dart';

void main() {
  test(
    'el editor recibe un avance remoto al quedar libre y conserva ramas locales',
    () async {
      final dir = await Directory.systemTemp.createTemp('nala-open-remote-');
      final repo = await SqliteNotebookRepository.open('${dir.path}/notes.db');
      final now = DateTime.utc(2026, 10, 6);
      final book = Notebook.blank(
        id: 'book',
        pageId: 'page',
        title: 'Original',
        subject: '',
        pattern: PaperPattern.blank,
        now: now,
      );
      final root = Revision(
        id: 'root',
        deviceId: 'A',
        parentId: null,
        createdAt: now,
        notebook: book,
      );
      await repo.acceptRemote(root);
      final editor = EditorController(
        notebook: book,
        headId: root.id,
        repository: repo,
        deviceId: 'B',
        newId: () => 'local',
        now: () => now,
      );
      try {
        await repo.acceptRemote(
          Revision(
            id: 'remote',
            deviceId: 'A',
            parentId: root.id,
            createdAt: now,
            notebook: book.copyWith(title: 'Remoto'),
          ),
        );
        expect(await editor.refreshRemote(canApply: () => false), isFalse);
        expect(editor.notebook.title, 'Original');
        expect(await editor.refreshRemote(canApply: () => true), isTrue);
        expect(editor.notebook.title, 'Remoto');
        expect(editor.headId, 'remote');
        await editor.apply((book) => book.copyWith(title: 'Mi cambio'));
        await repo.acceptRemote(
          Revision(
            id: 'other',
            deviceId: 'A',
            parentId: 'remote',
            createdAt: now,
            notebook: book.copyWith(title: 'Otro cambio'),
          ),
        );
        expect(await editor.refreshRemote(canApply: () => true), isFalse);
        expect(editor.notebook.title, 'Mi cambio');
        expect(await repo.list(), hasLength(2));
      } finally {
        editor.dispose();
        await repo.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
