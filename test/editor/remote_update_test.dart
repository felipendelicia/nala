import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/paper_canvas.dart';

import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  testWidgets('una entrada anterior al borrado no abre un editor activo', (
    tester,
  ) async {
    final book = fixtureNotebook();
    final repository = MemoryRepository();
    final initial = Revision(
      id: 'original',
      deviceId: 'tablet',
      parentId: null,
      createdAt: book.updatedAt,
      notebook: book,
    );
    await repository.acceptRemote(initial);
    final staleEntry = (await repository.list()).single;
    await repository.acceptRemote(
      Revision(
        id: Revision.deletionId('already-synced'),
        deviceId: 'tablet',
        parentId: initial.id,
        createdAt: book.updatedAt,
        notebook: book,
      ),
    );
    final editor = EditorController(
      notebook: staleEntry.notebook,
      headId: staleEntry.headId,
      repository: repository,
      deviceId: 'pc',
      newId: () => 'local',
      now: () => book.updatedAt,
    );
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      MaterialApp(home: EditorScreen(controller: editor)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PaperCanvas), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Cerrar apunte'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('una eliminación remota cierra la edición activa al terminar', (
    tester,
  ) async {
    final book = fixtureNotebook();
    final repository = MemoryRepository();
    final initial = Revision(
      id: 'origin',
      deviceId: 'tablet',
      parentId: null,
      createdAt: book.updatedAt,
      notebook: book,
    );
    await repository.acceptRemote(initial);
    final editor = EditorController(
      notebook: book,
      headId: initial.id,
      repository: repository,
      deviceId: 'pc',
      newId: () => 'local-edit',
      now: () => book.updatedAt,
    );
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      MaterialApp(home: EditorScreen(controller: editor)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PaperCanvas), findsOneWidget);

    await repository.acceptRemote(
      Revision(
        id: Revision.deletionId('remote'),
        deviceId: 'tablet',
        parentId: initial.id,
        createdAt: book.updatedAt,
        notebook: book,
      ),
    );
    expect(await editor.refreshRemote(canApply: () => false), isFalse);
    await editor.apply((book) => book.copyWith(title: 'Última edición local'));
    expect(await editor.refreshRemote(canApply: () => true), isTrue);
    await tester.pumpAndSettle();

    expect(
      find.text('El apunte se eliminó en otro dispositivo.'),
      findsOneWidget,
    );
    expect(find.byType(PaperCanvas), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Cerrar apunte'), findsOneWidget);
    expect(
      (await repository.history(book.id)).map((r) => r.id),
      contains('local-edit'),
    );
    await tester.pumpWidget(const SizedBox());
  });

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
