import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/library/library_controller.dart';
import '../support/fixtures.dart';

void main() {
  test('jerarquía y movimientos conservan apuntes al reabrir SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('nala-folders-');
    var repo = await SqliteNotebookRepository.open('${dir.path}/notes.db');
    var library = LibraryController(repository: repo, deviceId: 'pc');
    final university = await library.createFolder('Universidad');
    final subject = await library.createFolder(
      'Álgebra',
      parentId: university.id,
    );
    library.openFolder(subject.id);
    final unit = await library.createFolder('Unidad 1');
    library.openFolder(unit.id);
    final note = await library.createNotebook(
      title: 'Clase 1',
      subject: 'Matemática',
      pattern: PaperPattern.grid,
    );
    expect(note.notebook.folderId, unit.id);
    expect(library.breadcrumbs.map((f) => f.name), [
      'Universidad',
      'Álgebra',
      'Unidad 1',
    ]);
    await expectLater(
      library.moveFolder(university, unit.id),
      throwsStateError,
    );
    await expectLater(repo.deleteFolder(unit.id), throwsStateError);
    await expectLater(library.moveNotebook(note, 'missing'), throwsStateError);
    await library.moveNotebook(note, subject.id);
    await library.renameFolder(unit, 'Práctica');
    await library.moveFolder(unit, null);
    await repo.close();
    library.dispose();
    repo = await SqliteNotebookRepository.open('${dir.path}/notes.db');
    library = LibraryController(repository: repo, deviceId: 'pc');
    await library.refresh();
    library.openFolder(subject.id);
    expect(library.filtered().single.notebook.title, 'Clase 1');
    expect(
      library.filtered().single.notebook.pages.single.background.pattern,
      PaperPattern.grid,
    );
    expect(library.filtered().single.notebook.folderId, subject.id);
    expect(
      library.folders.singleWhere((f) => f.id == unit.id).name,
      'Práctica',
    );
    expect(
      library.folders.singleWhere((f) => f.id == unit.id).parentId,
      isNull,
    );
    await repo.deleteFolder(unit.id);
    await library.refresh();
    expect(library.folders.where((f) => f.id == unit.id), isEmpty);
    await repo.close();
    library.dispose();
    await dir.delete(recursive: true);
  });
  test(
    'formato anterior queda en raíz y ubicación nullable conserva hojas',
    () {
      final original = fixtureNotebook();
      final old = NotebookCodec.decode(NotebookCodec.encode(original));
      expect(old.folderId, isNull);
      final moved = NotebookCodec.decode(
        NotebookCodec.encode(old.copyWith(folderId: 'folder')),
      );
      expect(moved.folderId, 'folder');
      final root = moved.copyWith(folderId: null);
      expect(root.folderId, isNull);
      expect(root.pages.first.strokes.first.points.last.pressure, .75);
    },
  );
}
