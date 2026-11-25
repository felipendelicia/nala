import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/deferred_notebook_page.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/notebook_repository.dart';
import 'package:apuntes/document/page_comment.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:apuntes/editor/stroke_geometry.dart';
import 'package:apuntes/library/library_controller.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:apuntes/ui/app_theme.dart';
import 'package:apuntes/workspace/document_workspace.dart';
import 'package:apuntes/workspace/workspace_opening_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/memory_repository.dart';

class _CountingRepository extends MemoryRepository
    implements NotebookCatalogRepository {
  int catalogReads = 0;
  Completer<void>? pendingSave;
  Completer<Notebook?>? pendingLoad;
  final loadedHeads = <(String, String?)>[];

  @override
  Future<void> commit(Revision revision) async {
    await pendingSave?.future;
    await super.commit(revision);
  }

  @override
  Future<List<CatalogEntry>> listCatalog() async {
    catalogReads++;
    return [
      for (final entry in await super.list()) CatalogEntry.fromDocument(entry),
    ];
  }

  @override
  Future<Notebook?> load(String documentId, {String? headId}) {
    loadedHeads.add((documentId, headId));
    return pendingLoad?.future ?? super.load(documentId, headId: headId);
  }

  @override
  Future<NotebookPage?> loadPreview(
    String documentId, {
    required String headId,
  }) async => (await super.load(documentId, headId: headId))?.pages.first;
}

class _PageFirstRepository extends _CountingRepository
    implements EditableNotebookRepository {
  _PageFirstRepository(this.offscreen);

  final DeferredNotebookPage offscreen;
  final ready = Completer<void>();
  final editingRequests = <(String, String, int)>[];

  @override
  Future<Notebook?> load(String documentId, {String? headId}) async {
    loadedHeads.add((documentId, headId));
    throw StateError('La apertura no debe pedir la carga completa.');
  }

  @override
  Future<Notebook?> loadForEditing(
    String documentId, {
    required String headId,
    required int initialPageIndex,
    String? preparedPagePayload,
  }) async {
    editingRequests.add((documentId, headId, initialPageIndex));
    await ready.future;
    final notebook = revisions[headId]?.notebook;
    if (notebook == null || notebook.id != documentId) return null;
    final active = notebook.pages[initialPageIndex];
    final opened = DeferredNotebookPage(
      id: active.id,
      width: active.width,
      height: active.height,
      background: active.background,
      encoded: jsonEncode(active.toJson()),
      decoded: active,
    );
    return notebook.copyWith(
      pages: [
        for (final page in notebook.pages)
          if (page.id == offscreen.id)
            offscreen
          else if (page.id == opened.id)
            opened
          else
            page,
      ],
    );
  }
}

Future<String> _encodeSavedRevision(Revision revision) =>
    Isolate.run(() => NotebookCodec.encodeRevision(revision));

Future<_CountingRepository> _mountLibrary(
  WidgetTester tester, {
  bool reduceMotion = false,
  _CountingRepository? repository,
  Notebook? notebook,
}) async {
  await tester.binding.setSurfaceSize(const Size(820, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repo = repository ?? _CountingRepository();
  final library = LibraryController(repository: repo, deviceId: 'tablet');
  final services = AppServices(
    root: '/unused',
    deviceId: 'tablet',
    repository: repo,
    library: library,
    assets: MemoryAssets(),
  );
  addTearDown(services.close);
  await library.add(notebook ?? fixtureNotebook());
  await tester.pumpWidget(
    MaterialApp(
      theme: nalaTheme().copyWith(platform: TargetPlatform.android),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: LibraryScreen(services: services),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<_CountingRepository> _openNotebook(WidgetTester tester) async {
  final repository = await _mountLibrary(tester);
  await _tapNotebook(tester);
  return repository;
}

Finder _workspaceTransition(Type type, {Finder? child}) => find.ancestor(
  of: child ?? find.byType(WorkspaceScreen, skipOffstage: false),
  matching: find.byType(type, skipOffstage: false),
);

double _workspaceOpacity(WidgetTester tester, {Finder? child}) => tester
    .widget<FadeTransition>(_workspaceTransition(FadeTransition, child: child))
    .opacity
    .value;

Future<void> _tapNotebook(WidgetTester tester) async {
  await tester.tap(find.text(fixtureNotebook().title));
  await tester.pump();
  // Inspect the first painted frame after the route starts its fade.
  await tester.pump(const Duration(milliseconds: 11));
}

Finder get _openingHeader =>
    find.widgetWithText(AppBar, fixtureNotebook().title);

void main() {
  testWidgets('la entrada usa un fundido corto sin desplazamiento lateral', (
    tester,
  ) async {
    await _openNotebook(tester);
    expect(_openingHeader, findsOneWidget);
    expect(
      _workspaceTransition(SlideTransition, child: _openingHeader),
      findsNothing,
    );
    final left = tester.getTopLeft(_openingHeader).dx;
    final start = _workspaceOpacity(tester, child: _openingHeader);
    await tester.pump(const Duration(milliseconds: 22));
    expect(tester.getTopLeft(_openingHeader).dx, closeTo(left, .01));
    expect(
      _workspaceOpacity(tester, child: _openingHeader),
      greaterThan(start),
    );
    await tester.pump(const Duration(milliseconds: 110));
    final workspace = tester.element(find.byType(WorkspaceScreen));
    expect(
      ModalRoute.of(workspace)!.animation!.status,
      AnimationStatus.completed,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('el regreso difumina y recarga al terminar la transición', (
    tester,
  ) async {
    final repository = await _openNotebook(tester);
    await tester.pumpAndSettle();
    final before = repository.catalogReads;

    await tester.tap(find.byTooltip('Volver a mis apuntes'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(repository.catalogReads, before);
    expect(_workspaceOpacity(tester), lessThan(1));

    await tester.pumpAndSettle();
    expect(repository.catalogReads, before + 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('volver al catálogo espera el guardado pendiente', (
    tester,
  ) async {
    final repository = await _openNotebook(tester);
    await tester.pumpAndSettle();
    final editor = tester.widget<EditorScreen>(find.byType(EditorScreen));
    final save = repository.pendingSave = Completer<void>();
    unawaited(
      editor.controller.apply((note) => note.copyWith(title: 'Editado')),
    );

    await tester.tap(find.byTooltip('Volver a mis apuntes'));
    await tester.pump(const Duration(milliseconds: 250));
    final workspace = tester.element(find.byType(WorkspaceScreen));
    expect(ModalRoute.of(workspace)?.isCurrent, isTrue);
    expect(editor.controller.saving, isTrue);

    save.complete();
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceScreen), findsNothing);
    expect(find.text('Editado'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('el encabezado aparece antes de que termine la lectura', (
    tester,
  ) async {
    final repository = await _mountLibrary(tester);
    final load = repository.pendingLoad = Completer<Notebook?>();
    await _tapNotebook(tester);

    expect(_openingHeader, findsOneWidget);
    final openingRoute = ModalRoute.of(tester.element(_openingHeader));
    expect(find.byTooltip('Volver a mis apuntes'), findsOneWidget);
    expect(find.byType(EditorScreen), findsNothing);
    final loadingCanvas = find.descendant(
      of: find.byType(WorkspaceOpeningScreen),
      matching: find.byType(PaperCanvas),
    );
    expect(loadingCanvas, findsOneWidget);
    expect(loadingCanvas.hitTestable(), findsNothing);
    final displayed = tester.widget<PaperCanvas>(loadingCanvas).page;
    final previewPath = StrokeGeometry.canvasPath(displayed.strokes.single);
    expect(find.text('Cargando apunte…'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Cargando apunte…'), findsNothing);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Cargando apunte…'), findsOneWidget);

    final reread = fixtureNotebook();
    load.complete(reread);
    await tester.pump();
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(
      StrokeGeometry.canvasPath(reread.pages.first.strokes.single),
      same(previewPath),
    );
    expect(
      ModalRoute.of(tester.element(find.byType(WorkspaceScreen))),
      same(openingRoute),
    );
    expect(repository.loadedHeads, [
      (fixtureNotebook().id, repository.revisions.values.single.id),
    ]);
    expect(find.text('Cargando apunte…'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'abrir un resultado permite escribir sin hidratar hojas lejanas',
    (tester) async {
      final notebook = fixtureNotebook();
      final first = notebook.pages.single;
      NotebookPage blankPage(String id) => NotebookPage(
        id: id,
        width: first.width,
        height: first.height,
        background: first.background,
      );

      final distant = blankPage('page-5').copyWith(
        strokes: List.generate(
          2500,
          (index) => fixtureStroke(id: 'ink-$index'),
        ),
        recognizedText: 'Texto conservado en la última página',
      );
      const query = 'ecuación objetivo';
      final selected = blankPage('page-3').copyWith(
        comments: [
          PageComment(
            id: 'selected-comment',
            x: 20,
            y: 20,
            text: query,
            createdAt: notebook.updatedAt,
          ),
        ],
      );
      final offscreen = DeferredNotebookPage(
        id: distant.id,
        width: distant.width,
        height: distant.height,
        background: distant.background,
        encoded: jsonEncode(distant.toJson()),
      );
      final repository = _PageFirstRepository(offscreen);
      await _mountLibrary(
        tester,
        repository: repository,
        notebook: notebook.copyWith(
          pages: [
            first,
            blankPage('page-2'),
            selected,
            blankPage('page-4'),
            distant,
          ],
        ),
      );
      final originalHead = repository.revisions.keys.single;

      await tester.tap(find.byTooltip('Buscar en todos los apuntes'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText ==
                  'Título, materia, comentario o texto',
        ),
        query,
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Álgebra · página 3'));
      await tester.pumpAndSettle();

      expect(repository.loadedHeads, isEmpty);
      expect(repository.editingRequests, [(notebook.id, originalHead, 2)]);
      expect(find.byType(EditorScreen), findsNothing);
      repository.ready.complete();
      await tester.pumpAndSettle();

      final editor = tester.widget<EditorScreen>(find.byType(EditorScreen));
      expect(editor.controller.notebook.pages.last, same(offscreen));
      expect(offscreen.isReady, isFalse);
      final canvas = find.byWidgetPredicate(
        (widget) => widget is PaperCanvas && widget.page.id == 'page-3',
      );
      final bounds = tester.renderObject<RenderBox>(canvas);
      final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await pen.down(bounds.localToGlobal(const Offset(100, 120)));
      await pen.moveTo(bounds.localToGlobal(const Offset(130, 140)));
      await pen.up();
      await tester.pumpAndSettle();

      expect(offscreen.isReady, isFalse);
      expect(repository.loadedHeads, isEmpty);
      final committed = repository.revisions.values.singleWhere(
        (revision) => revision.parentId == originalHead,
      );
      final encoded = await tester.runAsync(
        () => _encodeSavedRevision(committed),
      );
      final saved = NotebookCodec.decodeRevision(encoded!);
      expect(offscreen.isReady, isFalse);
      expect(saved.parentId, originalHead);
      expect(saved.notebook.pages.map((page) => page.id), [
        'page-1',
        'page-2',
        'page-3',
        'page-4',
        'page-5',
      ]);
      final savedPage = saved.notebook.pages[2];
      final stroke = savedPage.strokes.single;
      expect(stroke.points.first.x, closeTo(100, .01));
      expect(stroke.points.first.y, closeTo(120, .01));
      expect(savedPage.comments.single.text, query);
      expect(saved.notebook.pages.last.toJson(), distant.toJson());
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('atrás cancela la apertura y descarta una respuesta tardía', (
    tester,
  ) async {
    final repository = await _mountLibrary(tester);
    final load = repository.pendingLoad = Completer<Notebook?>();
    await _tapNotebook(tester);
    expect(_openingHeader, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 130));

    await tester.binding.handlePopRoute();
    await tester.pump();
    load.complete(fixtureNotebook());
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.byType(EditorScreen, skipOffstage: false), findsNothing);
    await tester.pumpAndSettle();

    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(WorkspaceScreen), findsNothing);
    expect(find.byTooltip('Volver a mis apuntes'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('una revisión ausente muestra el error sin abrir el editor', (
    tester,
  ) async {
    final repository = await _mountLibrary(tester);
    final load = repository.pendingLoad = Completer<Notebook?>();
    await _tapNotebook(tester);
    load.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('El apunte ya no está disponible.'), findsOneWidget);
    expect(find.byType(EditorScreen), findsNothing);
    expect(find.byTooltip('Volver a mis apuntes'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('movimiento reducido muestra el encabezado sin transición', (
    tester,
  ) async {
    final repository = await _mountLibrary(tester, reduceMotion: true);
    final load = repository.pendingLoad = Completer<Notebook?>();
    await _tapNotebook(tester);
    final route = ModalRoute.of(tester.element(_openingHeader))!;
    expect(route.animation!.status, AnimationStatus.completed);

    load.complete(fixtureNotebook());
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceScreen), findsOneWidget);
    expect(_workspaceTransition(SlideTransition), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (tooltip, item) in [
    ('Más opciones de la biblioteca', 'Backup de la biblioteca'),
    ('Opciones de apunte', 'Eliminar apunte'),
  ]) {
    testWidgets('el menú $tooltip aparece completo con el primer toque', (
      tester,
    ) async {
      await _mountLibrary(tester);
      await tester.tap(find.byTooltip(tooltip));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final option = tester.element(find.text(item));
      expect(
        ModalRoute.of(option)!.animation!.status,
        AnimationStatus.completed,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
