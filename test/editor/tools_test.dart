import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/stroke_geometry.dart';
import '../support/fixtures.dart';

void main() {
  test('un borrador rápido detecta el cruce entre muestras', () {
    expect(StrokeGeometry.hitSweep(fixtureStroke(), const Point(0.0, 50.0), const Point(50.0, 0.0), 1), isTrue);
    expect(StrokeGeometry.hitSweep(fixtureStroke(), const Point(0.0, 100.0), const Point(50.0, 100.0), 1), isFalse);
  });
  test('presión y borrador tienen tamaño correcto entre puntos', () {
    expect(StrokeGeometry.widthFor(4, 0), 1.4);
    expect(StrokeGeometry.widthFor(4, 1), 4);
    expect(
      StrokeGeometry.hitTest(fixtureStroke(), const Point(20.0, 30.0), 1),
      isTrue,
    );
    expect(
      StrokeGeometry.hitTest(fixtureStroke(), const Point(100.0, 100.0), 1),
      isFalse,
    );
    final moved = StrokeGeometry.translate(fixtureStroke(), 10, -5);
    expect(moved.id, 'stroke-1');
    expect(moved.points.last.x, 40);
    expect(moved.points.first.y, 15);
  });
  test('borrar un gesto se deshace en una acción', () async {
    final dir = await Directory.systemTemp.createTemp('nala-tools-');
    final repo = await SqliteNotebookRepository.open('${dir.path}/notes.db');
    var id = 0;
    final editor = EditorController(
      notebook: fixtureNotebook(),
      repository: repo,
      deviceId: 'pc',
      newId: () => 'r${++id}',
      now: () => DateTime.utc(2026),
    );
    await editor.apply(
      (book) => book.copyWith(pages: [book.pages.first.copyWith(strokes: [])]),
    );
    expect(editor.notebook.pages.first.strokes, isEmpty);
    await editor.undo();
    expect(editor.notebook.pages.first.strokes.single.id, 'stroke-1');
    editor.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });
}
