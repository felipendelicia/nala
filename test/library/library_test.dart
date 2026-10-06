import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/library/library_controller.dart';

void main() {
  test(
    'crear, renombrar, deshacer y recuperar mantienen la escritura',
    () async {
      final dir = await Directory.systemTemp.createTemp('nala-library-');
      final repo = await SqliteNotebookRepository.open('${dir.path}/notes.db');
      addTearDown(() async {
        await repo.close();
        await dir.delete(recursive: true);
      });
      final library = LibraryController(repository: repo, deviceId: 'pc');
      final entry = await library.createNotebook(
        title: 'Álgebra',
        subject: 'Matemática',
        pattern: PaperPattern.dots,
      );
      var n = 0;
      final editor = EditorController(
        notebook: entry.notebook,
        repository: repo,
        deviceId: 'pc',
        newId: () => 'revision-${++n}',
        now: () => DateTime.utc(2026),
        headId: entry.headId,
      );
      await editor.apply((book) => book.copyWith(title: 'Álgebra II'));
      await editor.undo();
      await editor.flush();
      expect(editor.notebook.title, 'Álgebra');
      await editor.redo();
      await editor.flush();
      await library.refresh();
      expect(
        library
            .filtered(query: 'ALGEBRA', subject: 'Matemática')
            .single
            .notebook
            .title,
        'Álgebra II',
      );
      expect(library.filtered(subject: 'Física'), isEmpty);
      expect(
        (await repo.load(entry.notebook.id))!.pages.single.background.pattern,
        PaperPattern.dots,
      );
      editor.dispose();
      library.dispose();
    },
  );
}
