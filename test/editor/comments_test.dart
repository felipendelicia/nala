import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/page_comment.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  testWidgets('anclar, editar, consultar en lectura y borrar un comentario', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var revision = 0;
    final controller = EditorController(
      notebook: fixtureNotebook(),
      repository: MemoryRepository(),
      deviceId: 'pc',
      newId: () => 'r${++revision}',
      now: () => DateTime.utc(2026),
    );
    await tester.pumpWidget(
      MaterialApp(home: EditorScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Comentarios'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar comentario'));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(PaperCanvas)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Repasar antes del parcial');
    await tester.tap(find.text('Guardar comentario'));
    await tester.pumpAndSettle();
    expect(
      controller.notebook.pages.first.comments.single.text,
      'Repasar antes del parcial',
    );
    expect(controller.notebook.pages.first.strokes, hasLength(1));
    await tester.tap(find.text('Repasar antes del parcial'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Consultar con el profesor');
    await tester.tap(find.text('Guardar comentario'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Modo lectura'));
    await tester.pumpAndSettle();
    expect(find.text('Agregar comentario'), findsNothing);
    expect(find.byTooltip('Eliminar comentario'), findsNothing);
    await tester.tap(find.text('Consultar con el profesor'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Guardar comentario'), findsNothing);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Modo editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eliminar comentario'));
    await tester.pumpAndSettle();
    expect(controller.notebook.pages.first.comments, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  test('comentarios de texto y voz conservan anclaje y audio al reabrir', () {
    final old = fixtureNotebook();
    expect(
      NotebookCodec.decode(NotebookCodec.encode(old)).pages.first.comments,
      isEmpty,
    );
    final comment = PageComment(
      id: 'comment-1',
      x: 25,
      y: 40,
      text: 'Revisar teorema',
      createdAt: DateTime.utc(2026),
      audioAssetId: 'a' * 64,
      audioDurationMs: 3200,
    );
    final note = old.copyWith(
      pages: [
        old.pages.first.copyWith(comments: [comment]),
      ],
    );
    final restored = NotebookCodec.decode(NotebookCodec.encode(note));
    final result = restored.pages.first.comments.single;
    expect(result.text, 'Revisar teorema');
    expect(result.x, 25);
    expect(result.y, 40);
    expect(result.audioDurationMs, 3200);
    expect(result.audioAssetId, 'a' * 64);
    expect(restored.pages.first.strokes.single.points.last.pressure, .75);
    final invalid =
        jsonDecode(NotebookCodec.encode(note)) as Map<String, dynamic>;
    invalid['pages'][0]['comments'][0]['audioAssetId'] = '../secret';
    expect(
      () => NotebookCodec.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
    final duplicate = note.copyWith(
      pages: [
        note.pages.first.copyWith(comments: [comment, comment]),
      ],
    );
    expect(
      () => NotebookCodec.decode(NotebookCodec.encode(duplicate)),
      throwsFormatException,
    );
  });
}
