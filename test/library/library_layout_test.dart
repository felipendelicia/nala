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
import 'package:apuntes/library/library_controller.dart';
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

void main() {
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
      await tester.tap(find.text('Crear cuaderno'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Nombre del cuaderno'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await services.close();
    });
  }
}
