import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/editor/editor_controller.dart';
import '../support/fixtures.dart';

void main() {
  test('un guardado fallido conserva memoria y permite reintentar', () async {
    final dir = await Directory.systemTemp.createTemp('nala-save-');
    final path = '${dir.path}/notes.db';
    final repo = await SqliteNotebookRepository.open(path);
    final sql = sqlite3.open(path);
    sql.execute(
      "CREATE TRIGGER fail_queue BEFORE INSERT ON upload_queue BEGIN SELECT RAISE(ABORT,'disk failure'); END",
    );
    var id = 0;
    final editor = EditorController(
      notebook: fixtureNotebook(),
      repository: repo,
      deviceId: 'pc',
      newId: () => 'r${++id}',
      now: () => DateTime.utc(2026),
    );
    await editor.apply((book) => book.copyWith(title: 'Conservar en memoria'));
    expect(editor.savingError, isNotNull);
    expect(editor.headId, isNull);
    expect(editor.notebook.title, 'Conservar en memoria');
    await expectLater(editor.flush(), throwsStateError);
    sql.execute('DROP TRIGGER fail_queue');
    sql.close();
    await editor.retrySave();
    await editor.flush();
    expect(editor.savingError, isNull);
    expect((await repo.load('doc-1'))!.title, 'Conservar en memoria');
    editor.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });
}
