import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:apuntes/app.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/pdf/document_files.dart';
import '../test/support/pdf_fixtures.dart';
import 'support/capture.dart';

class TestDocumentFiles implements DocumentFiles {
  TestDocumentFiles(this.bytes);
  final Uint8List bytes;
  Uint8List? saved;
  bool cancelSave = false;
  @override
  Future<SelectedPdf?> openPdf() async =>
      SelectedPdf(bytes: bytes, name: 'Guía.pdf');
  @override
  Future<bool> savePdf(Uint8List bytes, {required String name}) async {
    if (cancelSave) return false;
    saved = bytes;
    return true;
  }
}

// Native I/O and worker isolates can be busy even when no frame is scheduled.
// Wait for the result itself instead of treating pumpAndSettle as an I/O barrier.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  final timer = Stopwatch()..start();
  while (!ready()) {
    if (timer.elapsed > const Duration(seconds: 60)) {
      fail(
        'Timeout esperando $description. Textos: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | ')}',
      );
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'importar, anotar, insertar hoja y exportar conserva el cuaderno',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('nala-pdf-flow-');
      final files = TestDocumentFiles(await makeFixturePdf());
      final services = await AppServices.open(dir.path, files: files);
      const previewKey = ValueKey('pdf-preview');
      await tester.pumpWidget(
        RepaintBoundary(
          key: previewKey,
          child: NalaApp(services: services),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir PDF'));
      debugPrint('pdf-flow: waiting for import');
      await pumpUntil(
        tester,
        () => find.byType(EditorScreen).evaluate().isNotEmpty,
        'el editor del PDF',
      );
      await tester.pumpAndSettle();
      debugPrint('pdf-flow: editor ready');
      expect(
        find.text('Guía'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join(' | '),
      );
      final canvas = find.byType(PaperCanvas).first;
      final center = tester.getCenter(canvas);
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.stylus,
      );
      await gesture.moveBy(const Offset(20, 20));
      await gesture.up();
      await tester.pumpAndSettle();
      debugPrint('pdf-flow: stroke drawn');
      await captureUi(tester, find.byKey(previewKey), 'pdf-editor');
      await tester.tap(find.byTooltip('Agregar hoja').first);
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
      await tester.tap(find.byTooltip('Exportar PDF'));
      debugPrint('pdf-flow: export requested');
      // The editor must remain usable while the worker prepares PDF pixels.
      await tester.pump();
      await tester.tap(find.byTooltip('Hoja siguiente'));
      await tester.pump();
      expect(find.text('3/3'), findsOneWidget);
      await pumpUntil(tester, () => files.saved != null, 'el PDF exportado');
      debugPrint('pdf-flow: export received');
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 60),
      );
      expect(files.saved, isNotNull);
      await captureUi(tester, find.byKey(previewKey), 'pdf-navigation');
      final output = await PdfDocument.openData(files.saved!);
      expect(output.pages.length, 3);
      await output.dispose();
      files.cancelSave = true;
      await tester.tap(find.byTooltip('Exportar PDF'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 60),
      );
      await tester.tap(find.byTooltip('Volver a mis apuntes'));
      await tester.pumpAndSettle();
      final saved = (await services.repository.list()).single.notebook;
      expect(saved.pages, hasLength(3));
      expect(saved.pages[0].strokes, hasLength(1));
      expect(saved.pages[0].background.pageNumber, 1);
      expect(saved.pages[1].background.pattern, isNotNull);
      expect(saved.pages[2].background.pageNumber, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await services.close();
      debugPrint('pdf-flow: services closed');
      await dir.delete(recursive: true);
    },
  );
}
