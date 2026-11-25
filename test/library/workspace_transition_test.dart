import 'dart:async';

import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_repository.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/library/library_controller.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:apuntes/ui/app_theme.dart';
import 'package:apuntes/workspace/document_workspace.dart';
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

Future<_CountingRepository> _mountLibrary(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(820, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _CountingRepository();
  final library = LibraryController(repository: repository, deviceId: 'tablet');
  final services = AppServices(
    root: '/unused',
    deviceId: 'tablet',
    repository: repository,
    library: library,
    assets: MemoryAssets(),
  );
  addTearDown(services.close);
  final note = fixtureNotebook();
  await library.add(note);
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
  return repository;
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
    expect(find.text('Cargando apunte…'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Cargando apunte…'), findsNothing);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Cargando apunte…'), findsOneWidget);

    load.complete(fixtureNotebook());
    await tester.pump();
    expect(find.byType(EditorScreen), findsOneWidget);
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
