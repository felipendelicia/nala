import 'dart:io';

import 'package:apuntes/ai/chat_gpt_client.dart';
import 'package:apuntes/ai/notebook_chat_store.dart';
import 'package:apuntes/ai/notebook_study_service.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/pdf/pdf_export_service.dart';
import 'package:apuntes/pdf/pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/memory_repository.dart';

class _ConnectedClient extends ChatGptClient {
  @override
  bool get connected => true;

  @override
  Future<void> load() async {}
}

class _StudyService extends NotebookStudyService {
  _StudyService(ChatGptClient client)
    : super(
        client: client,
        exporter: PdfExportService(PdfService(assets: MemoryAssets())),
      );

  @override
  Future<String> ask({
    required Notebook notebook,
    required List<String> pageIds,
    required List<NotebookChatMessage> messages,
    Future<bool> Function(String assetId)? unlock,
    void Function(String)? onDelta,
  }) async => switch (messages.last.text) {
    '¿Qué es una derivada?' => 'Una derivada mide el cambio.',
    '¿Qué es un límite?' => 'Un límite describe el valor al que se acerca.',
    _ => throw StateError('Pregunta inesperada'),
  };
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget);
}

void main() {
  testWidgets(
    'ChatGPT abre los chats del apunte y guarda las hojas elegidas por pregunta',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('nala-study-'),
      ))!;
      addTearDown(() => root.delete(recursive: true));
      final client = _ConnectedClient();
      addTearDown(client.dispose);
      final study = _StudyService(client);
      final repository = MemoryRepository();
      final notebook = fixtureNotebook();
      final chatStore = NotebookChatStore(root.path);
      var revision = 0;
      final controller = EditorController(
        notebook: notebook.copyWith(
          pages: [
            ...notebook.pages,
            NotebookPage(
              id: 'page-2',
              width: 595.28,
              height: 841.89,
              background: const PageBackground.paper(PaperPattern.grid),
            ),
          ],
        ),
        repository: repository,
        deviceId: 'test',
        newId: () => 'study-revision-${revision++}',
        now: () => DateTime.utc(2026),
      );
      addTearDown(controller.dispose);
      await tester.binding.setSurfaceSize(const Size(1200, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            home: EditorScreen(
              controller: controller,
              chatGpt: client,
              chatStore: chatStore,
              studyService: study,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('ChatGPT'));
        await _waitFor(tester, find.byType(TextField));
      }

      await open();
      expect(find.text('Todas las hojas'), findsOneWidget);
      expect(find.byTooltip('Historial de chats'), findsOneWidget);
      expect(find.byTooltip('Nuevo chat'), findsOneWidget);
      expect(find.text('Resumen'), findsNothing);
      expect(find.text('Crear hoja de resumen'), findsNothing);
      await tester.enterText(find.byType(TextField), '¿Qué es una derivada?');
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar pregunta'));
      await _waitFor(
        tester,
        find.text('Una derivada mide el cambio.', findRichText: true),
      );
      await _waitFor(tester, find.byType(TextField));
      await tester.pumpWidget(const SizedBox.shrink());

      await open();
      expect(find.text('¿Qué es una derivada?'), findsOneWidget);
      expect(
        find.text('Una derivada mide el cambio.', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Nuevo chat'));
      await tester.pumpAndSettle();
      expect(find.text('Todas las hojas'), findsOneWidget);
      await tester.tap(find.text('Cambiar páginas'));
      await tester.pumpAndSettle();
      expect(find.text('2 hojas seleccionadas'), findsOneWidget);
      await tester.tap(find.text('Hoja 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usar selección'));
      await tester.pumpAndSettle();
      expect(find.text('Hoja 1'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '¿Qué es un límite?');
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar pregunta'));
      await _waitFor(
        tester,
        find.text(
          'Un límite describe el valor al que se acerca.',
          findRichText: true,
        ),
      );
      await _waitFor(tester, find.byType(TextField));
      final chats = (await tester.runAsync(() => chatStore.list(notebook.id)))!;
      expect(chats.map((chat) => chat.title), [
        '¿Qué es un límite?',
        '¿Qué es una derivada?',
      ]);
      expect(chats.first.messages.first.pageIds, ['page-1']);
      expect(chats.last.messages.first.pageIds, ['page-1', 'page-2']);

      await tester.tap(find.byTooltip('Historial de chats'));
      await tester.pumpAndSettle();
      expect(find.text('¿Qué es un límite?'), findsOneWidget);
      await tester.tap(find.text('¿Qué es una derivada?'));
      await tester.pumpAndSettle();
      expect(
        find.text('Una derivada mide el cambio.', findRichText: true),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('las hojas Markdown guardadas se pueden editar', (tester) async {
    final repository = MemoryRepository();
    final fixture = fixtureNotebook();
    final original = fixture.pages.single.copyWith(markdown: '# Mis notas');
    final notebook = fixture.copyWith(pages: [original]);
    final controller = EditorController(
      notebook: notebook,
      repository: repository,
      deviceId: 'test',
      newId: () => 'edición-notas',
      now: () => DateTime.utc(2026),
    );
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: EditorScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mis notas', findRichText: true), findsOneWidget);
    await tester.tap(find.byTooltip('Opciones del cuaderno'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar Markdown'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '# Notas revisadas');
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await _waitFor(tester, find.text('Notas revisadas', findRichText: true));
    final saved = (await repository.load(notebook.id))!.pages.single;
    expect(saved.markdown, '# Notas revisadas');
    expect(saved.id, original.id);
    expect(
      saved.strokes.map((stroke) => stroke.id),
      original.strokes.map((stroke) => stroke.id),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
