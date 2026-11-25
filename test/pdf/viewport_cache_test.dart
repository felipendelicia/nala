import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/zoom_controls.dart';
import 'package:apuntes/pdf/pdf_page_background.dart';
import 'package:apuntes/pdf/pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_repository.dart';
import '../support/pdf_engine.dart';
import '../support/pdf_fixtures.dart';

class CountingAssets extends MemoryAssets {
  int reads = 0;

  @override
  Future<Uint8List> read(String id) {
    reads++;
    return super.read(id);
  }
}

class DelayedPdf extends PdfService {
  DelayedPdf() : super(assets: MemoryAssets());

  final exact = Completer<Uint8List>();

  @override
  Future<Uint8List> renderBackground(
    String id,
    int number, {
    required double scale,
    PdfRenderCancellation? cancellation,
  }) => exact.future;
}

Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
  final timeout = Stopwatch()..start();
  while (!condition() && timeout.elapsed < const Duration(seconds: 10)) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(condition(), isTrue, reason: 'El render PDF no terminó a tiempo.');
}

void main() {
  testWidgets(
    'el fondo muestra el caché mientras obtiene el PDF de mayor resolución',
    (tester) async {
      final pdf = DelayedPdf();
      addTearDown(pdf.dispose);
      final assetId = 'a' * 64;
      final preview = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGNgAAAAAgABSK+kcQAAAABJRU5ErkJggg==',
      );
      pdf.cache.put(
        (assetId: assetId, pageNumber: 1, scaleStep: 4),
        preview,
        decodedBytes: 4,
      );
      final page = NotebookPage(
        id: 'pdf-1',
        width: 200,
        height: 200,
        background: PageBackground.pdf(assetId, 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PdfPageBackground(pdf: pdf, page: page, scale: 2),
        ),
      );
      expect(pdf.exact.isCompleted, isFalse);
      expect(find.byType(Image), findsOneWidget);
      expect(
        (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
        same(preview),
      );

      final full = Uint8List.fromList(preview);
      pdf.exact.complete(full);
      await tester.pump();
      expect(
        (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
        same(full),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'la segunda página PDF a DPR 2 reutiliza el único raster precargado',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('nala-pdf-cache-test-'),
      ))!;
      addTearDown(() => temp.delete(recursive: true));
      final assets = CountingAssets();
      final pdf = PdfService(
        assets: assets,
        initialize: () => initializePdfForTest(temp.path),
      );
      addTearDown(pdf.dispose);
      var id = 0;
      final book = (await tester.runAsync(
        () async => pdf.importDocument(
          bytes: await makeFixturePdf(),
          title: 'PDF de prueba',
          documentId: 'pdf',
          newId: () => 'p${++id}',
          now: DateTime.utc(2026),
        ),
      ))!;
      final controller = EditorController(
        notebook: book,
        repository: MemoryRepository(),
        deviceId: 'tablet',
        newId: () => 'r${++id}',
        now: () => DateTime.utc(2026),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: EditorScreen(controller: controller, pdf: pdf),
        ),
      );
      expect(find.byType(PdfPageBackground), findsOneWidget);
      final assetId = book.pages.first.background.assetId!;
      await pumpUntil(tester, () => pdf.cache.latestFor(assetId, 2) != null);
      final readsBefore = assets.reads;
      final rasterScale =
          tester.widget<ZoomControls>(find.byType(ZoomControls)).scale * 2;
      expect(readsBefore, 2);

      await tester.tap(find.byTooltip('Hoja siguiente'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => pdf.cachedBackground(assetId, 2, scale: rasterScale) != null,
      );
      expect(
        assets.reads,
        readsBefore,
        reason: 'La hoja siguiente no debe rasterizarse otra vez.',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
