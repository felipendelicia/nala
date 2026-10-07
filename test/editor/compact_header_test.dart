import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:apuntes/pdf/pdf_service.dart';
import 'package:apuntes/pdf/pdf_share.dart';
import 'package:apuntes/pdf/document_files.dart';
import 'package:apuntes/ui/app_theme.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  testWidgets('compact popup controls retain finger targets', (tester) async {
    final controller = EditorController(
      notebook: fixtureNotebook(),
      repository: MemoryRepository(),
      deviceId: 'test',
      newId: () => 'revision',
      now: () => DateTime.utc(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: nalaTheme(),
        home: EditorScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['Grosor de tinta', 'Tipo de hoja']) {
      expect(
        tester.getSize(find.byTooltip(label)).height,
        greaterThanOrEqualTo(48),
        reason: label,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  for (final size in [
    const Size(400, 650),
    const Size(800, 1200),
    const Size(1200, 800),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'compact header preserves canvas when tools open $size/$brightness',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final controller = EditorController(
            notebook: fixtureNotebook().copyWith(
              title: 'Un título largo para la hoja de Álgebra',
            ),
            repository: MemoryRepository(),
            deviceId: 'test',
            newId: () => 'revision',
            now: () => DateTime.utc(2026),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: nalaTheme(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: EditorScreen(
                controller: controller,
                pdf: PdfService(assets: MemoryAssets()),
                share: NativePdfShare(),
                files: NativeDocumentFiles(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final viewport = find.byKey(const ValueKey('document-viewport'));
          final rect = tester.getRect(viewport);
          expect(
            rect.top,
            lessThanOrEqualTo(112),
            reason: 'Two compact rows leave the rest to the page.',
          );
          final paper = tester.getRect(find.byType(PaperCanvas).first);
          final tools = find.byTooltip('Más herramientas');
          expect(tester.getSize(tools).shortestSide, greaterThanOrEqualTo(44));
          await tester.tap(tools);
          await tester.pumpAndSettle();
          expect(tester.getRect(viewport), rect);
          expect(tester.getRect(find.byType(PaperCanvas).first), paper);
          expect(find.byTooltip('Formas'), findsOneWidget);
          expect(find.byTooltip('Tarjetas de estudio'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Cerrar herramientas'));
          await tester.pumpAndSettle();
          expect(tester.getRect(viewport), rect);
          await tester.tap(find.byTooltip('Modo lectura'));
          await tester.pumpAndSettle();
          expect(tester.getRect(viewport).top, lessThanOrEqualTo(56));
          await tester.tap(find.byTooltip('Más herramientas'));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Formas'), findsNothing);
          expect(find.byTooltip('Tarjetas de estudio'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        },
      );
    }
  }
}
