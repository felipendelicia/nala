import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:apuntes/ui/app_theme.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/folders.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_repository.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:apuntes/library/library_controller.dart';
import 'package:apuntes/workspace/document_workspace.dart';
import '../support/memory_repository.dart';

class _CountingCovers extends MemoryAssets {
  _CountingCovers(this.image);

  final Uint8List image;
  final reads = <String>[];

  @override
  Future<Uint8List> read(String id) async {
    reads.add(id);
    return image;
  }
}

class _CountingCatalog extends MemoryRepository
    implements NotebookCatalogRepository {
  int fullLists = 0;
  final opened = <(String, String?)>[];
  final previews = <String>[];
  final delayedPreviews = <String, Completer<NotebookPage?>>{};

  @override
  Future<List<DocumentEntry>> list() {
    fullLists++;
    return super.list();
  }

  @override
  Future<List<CatalogEntry>> listCatalog() async => [
    for (final entry in await super.list()) CatalogEntry.fromDocument(entry),
  ];

  @override
  Future<Notebook?> load(String documentId, {String? headId}) {
    opened.add((documentId, headId));
    return super.load(documentId, headId: headId);
  }

  @override
  Future<NotebookPage?> loadPreview(
    String documentId, {
    required String headId,
  }) async {
    previews.add(headId);
    final delayed = delayedPreviews[headId];
    if (delayed != null) return delayed.future;
    return (await super.load(documentId, headId: headId))?.pages.first;
  }
}

Revision _catalogRevision(int index, {String? parent, bool cover = false}) =>
    Revision(
      id: 'head-$index',
      deviceId: 'tab',
      parentId: parent,
      createdAt: DateTime.utc(2026),
      notebook: Notebook.blank(
        id: 'apunte-${parent == null ? index : 0}',
        pageId: 'page-$index',
        title: 'Apunte $index',
        subject: '',
        pattern: PaperPattern.grid,
        now: DateTime.utc(2026),
      ).copyWith(coverAssetId: cover ? 'c' * 64 : null),
    );

void main() {
  testWidgets('el catálogo solo carga las vistas previas visibles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(820, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _CountingCatalog();
    final library = LibraryController(repository: repository, deviceId: 'tab');
    final services = AppServices(
      root: '/unused',
      deviceId: 'tab',
      repository: repository,
      assets: MemoryAssets(),
      library: library,
    );
    addTearDown(services.close);
    for (var i = 0; i < 30; i++) {
      await repository.acceptRemote(_catalogRevision(i, cover: i == 1));
    }
    await library.refresh();
    expect(repository.previews, isEmpty);
    await tester.pumpWidget(
      MaterialApp(home: LibraryScreen(services: services)),
    );
    await tester.pumpAndSettle();

    expect(repository.fullLists, 0);
    expect(repository.opened, isEmpty);
    expect(repository.previews, contains('head-0'));
    expect(repository.previews, isNot(contains('head-1')));
    expect(repository.previews, isNot(contains('head-29')));

    await tester.tap(find.text('Apunte 0'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceScreen), findsOneWidget);
    expect(repository.opened, [('apunte-0', 'head-0')]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('una vista previa tardía no reemplaza la revisión nueva', (
    tester,
  ) async {
    final repository = _CountingCatalog();
    final library = LibraryController(repository: repository, deviceId: 'tab');
    final services = AppServices(
      root: '/unused',
      deviceId: 'tab',
      repository: repository,
      assets: MemoryAssets(),
      library: library,
    );
    addTearDown(services.close);
    final original = _catalogRevision(0);
    final pending = Completer<NotebookPage?>();
    repository.delayedPreviews[original.id] = pending;
    await repository.acceptRemote(original);
    await library.refresh();
    await tester.pumpWidget(
      MaterialApp(home: LibraryScreen(services: services)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PaperCanvas), findsNothing);

    await repository.acceptRemote(_catalogRevision(1, parent: original.id));
    await library.refresh();
    await tester.pumpAndSettle();
    expect(
      tester.widget<PaperCanvas>(find.byType(PaperCanvas)).page.id,
      'page-1',
    );

    pending.complete(original.notebook.pages.first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<PaperCanvas>(find.byType(PaperCanvas)).page.id,
      'page-1',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('una portada visible no se vuelve a leer al filtrar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(820, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MemoryRepository();
    final library = LibraryController(repository: repository, deviceId: 'tab');
    final assets = _CountingCovers(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGNgAAAAAgABSK+kcQAAAABJRU5ErkJggg==',
      ),
    );
    final services = AppServices(
      root: '/unused',
      deviceId: 'tab',
      repository: repository,
      assets: assets,
      library: library,
    );
    addTearDown(services.close);
    final algebra = Notebook.blank(
      id: 'algebra',
      pageId: 'page',
      title: 'Álgebra',
      subject: '',
      pattern: PaperPattern.grid,
      now: DateTime.utc(2026),
    );
    final otherCover = 'c' * 64;
    await library.add(
      Notebook.blank(
        id: 'physics',
        pageId: 'physics-page',
        title: 'Física',
        subject: '',
        pattern: PaperPattern.grid,
        now: DateTime.utc(2026),
      ).copyWith(coverAssetId: otherCover),
    );
    final cover = 'a' * 64;
    final updatedCover = 'b' * 64;
    final entry = await library.add(algebra.copyWith(coverAssetId: cover));
    await tester.pumpWidget(
      MaterialApp(home: LibraryScreen(services: services)),
    );
    await tester.pumpAndSettle();
    expect(assets.reads, unorderedEquals([otherCover, cover]));

    await tester.enterText(find.byType(TextField), 'ALGEBRA');
    await tester.pumpAndSettle();
    expect(find.text('Álgebra'), findsOneWidget);
    expect(find.text('Física'), findsNothing);
    expect(assets.reads, unorderedEquals([otherCover, cover]));

    await library.updateNotebook(
      entry,
      algebra.copyWith(coverAssetId: updatedCover),
    );
    await tester.pumpAndSettle();
    expect(assets.reads, unorderedEquals([otherCover, cover, updatedCover]));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'biblioteca poblada muestra título y materia en una ventana de PC',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fonts = FontLoader('Manrope')
        ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
      await fonts.load();
      final repository = MemoryRepository();
      final library = LibraryController(repository: repository, deviceId: 'pc');
      final services = AppServices(
        root: '/unused',
        deviceId: 'pc',
        repository: repository,
        assets: FileAssetStore('/unused/assets'),
        library: library,
      );
      for (final subject in ['Análisis', 'Física']) {
        await library.createNotebook(
          title: '$subject — Guía de ejercicios',
          subject: subject,
          pattern: PaperPattern.grid,
        );
      }
      library.folders = [NoteFolder(id: 'folder', name: 'Universidad')];
      await tester.pumpWidget(
        MaterialApp(
          theme: nalaTheme(),
          home: LibraryScreen(services: services),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(GridView));
      for (final subject in ['Análisis', 'Física']) {
        expect(
          tester.getRect(find.text('$subject — Guía de ejercicios')).bottom,
          lessThanOrEqualTo(viewport.bottom),
        );
        expect(
          tester.getRect(find.text(subject)).bottom,
          lessThanOrEqualTo(viewport.bottom),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await services.close();
    },
  );
  for (final size in [
    const Size(1200, 800),
    const Size(800, 1200),
    const Size(1440, 900),
  ]) {
    testWidgets('biblioteca vacía usable en $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = MemoryRepository();
      final services = AppServices(
        root: '/unused',
        deviceId: 'pc',
        repository: repository,
        assets: FileAssetStore('/unused/assets'),
        library: LibraryController(repository: repository, deviceId: 'pc'),
      );
      await services.library.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: nalaTheme(brightness: Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: LibraryScreen(services: services),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Crear cuaderno'), findsOneWidget);
      expect(find.text('Transcribir clase'), findsNothing);
      await tester.tap(find.text('Crear cuaderno'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Nombre del cuaderno'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Materia'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await services.close();
    });
  }
}
