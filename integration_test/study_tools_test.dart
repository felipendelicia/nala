import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:apuntes/app.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/page_object.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:apuntes/pdf/pdf_export_service.dart';
import 'package:apuntes/search/notebook_search_dialog.dart';
import 'support/capture.dart';

Future<void> waitStudy(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready()) {
    if (watch.elapsed.inSeconds > 60) {
      fail('La operación de estudio no terminó.');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> tapStudy(WidgetTester tester, String tooltip) async {
  var target = find.byTooltip(tooltip);
  if (target.evaluate().isEmpty) {
    final notebookOption = {
      'Abrir otro apunte',
      'Vista dividida',
      'Exportar PDF',
    }.contains(tooltip);
    await tester.tap(
      find
          .byTooltip(
            notebookOption ? 'Opciones del cuaderno' : 'Más herramientas',
          )
          .first,
    );
    await tester.pumpAndSettle();
    target = notebookOption ? find.text(tooltip) : find.byTooltip(tooltip);
  }
  target = target.first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('texto, formas, plantillas, búsqueda, tarjetas y dos cuadernos', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('nala-study-native-');
    final services = await AppServices.open(root.path);
    final first = await services.library.createNotebook(
      title: 'Álgebra',
      subject: 'Universidad',
      pattern: PaperPattern.blank,
    );
    final second = await services.library.createNotebook(
      title: 'Análisis',
      subject: 'Universidad',
      pattern: PaperPattern.grid,
    );
    const preview = ValueKey('study-preview');
    await tester.pumpWidget(
      RepaintBoundary(
        key: preview,
        child: NalaApp(services: services),
      ),
    );
    await waitStudy(
      tester,
      () => find.byType(LibraryScreen).evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Álgebra'));
    await waitStudy(
      tester,
      () => find.byType(EditorScreen).evaluate().isNotEmpty,
    );
    final controller = tester
        .widget<EditorScreen>(find.byType(EditorScreen))
        .controller;
    await captureUi(tester, find.byKey(preview), 'compact-editor-v051');
    await tapStudy(tester, 'Más herramientas');
    await captureUi(tester, find.byKey(preview), 'compact-tools-v051');
    await tapStudy(tester, 'Cerrar herramientas');
    await tapStudy(tester, 'Insertar texto');
    await tester.enterText(
      find.bySemanticsLabel('Texto'),
      'Límite y continuidad',
    );
    await tester.pump();
    await tester.tap(find.text('Insertar'));
    await waitStudy(
      tester,
      () => controller.notebook.pages.first.objects.isNotEmpty,
    );
    await tapStudy(tester, 'Duplicar selección');
    expect(controller.notebook.pages.first.objects, hasLength(2));
    await tapStudy(tester, 'Deshacer');
    expect(controller.notebook.pages.first.objects, hasLength(1));
    await tapStudy(tester, 'Formas');
    await tester.tap(find.text('Rectángulo'));
    await tester.pumpAndSettle();
    final box = tester.renderObject<RenderBox>(find.byType(PaperCanvas).first);
    final pen = await tester.startGesture(
      box.localToGlobal(const Offset(70, 220)),
      kind: PointerDeviceKind.stylus,
    );
    await pen.moveTo(box.localToGlobal(const Offset(230, 320)));
    await pen.up();
    await tester.pumpAndSettle();
    expect(controller.notebook.pages.first.strokes.single.points, hasLength(5));
    await tapStudy(tester, 'Plantillas y portadas');
    await waitStudy(tester, () => find.text('Cornell').evaluate().isNotEmpty);
    await tester.ensureVisible(find.text('Cornell'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cornell'));
    await waitStudy(
      tester,
      () => find.text('Aplicar a esta hoja').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Aplicar a esta hoja'));
    await tester.pumpAndSettle();
    expect(
      controller.notebook.pages.first.background.pattern,
      PaperPattern.cornell,
    );
    await tapStudy(tester, 'Buscar en apunte');
    await tester.enterText(find.byType(TextField), 'limite');
    final searchHit = find.widgetWithText(ListTile, 'Álgebra · página 1');
    await waitStudy(tester, () => searchHit.evaluate().isNotEmpty);
    await tester.tap(searchHit);
    await waitStudy(
      tester,
      () => find.byType(NotebookSearchDialog).evaluate().isEmpty,
    );
    await tapStudy(tester, 'Tarjetas de estudio');
    await tester.tap(find.text('Nueva tarjeta'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      '¿Qué es un límite?',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'El valor al que se aproxima una función.',
    );
    await tester.tap(find.text('Guardar tarjeta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repasar pendientes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mostrar respuesta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bien'));
    await tester.pumpAndSettle();
    expect(controller.notebook.studyCards.single.repetitions, 1);
    await captureUi(tester, find.byKey(preview), 'study-cards-v051');
    await tapStudy(tester, 'Cerrar estudio');
    final image = img.Image(width: 160, height: 100);
    img.fill(image, color: img.ColorRgb8(200, 220, 250));
    final assetId = await services.assets.put(img.encodePng(image));
    await controller.apply(
      (n) => n.copyWith(
        pages: [
          n.pages.first.copyWith(
            objects: [
              ...n.pages.first.objects,
              PageObject(
                id: 'diagram',
                kind: PageObjectKind.image,
                x: 280,
                y: 240,
                width: 160,
                height: 100,
                assetId: assetId,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await captureUi(tester, find.byKey(preview), 'study-editor-v051');
    final bytes = await PdfExportService(
      services.pdf,
    ).export(controller.notebook);
    await File('.dart_tool/ui-qa/study-export-v051.pdf').writeAsBytes(bytes);
    await tapStudy(tester, 'Abrir otro apunte');
    await tester.tap(find.text('Análisis').last);
    await tester.pumpAndSettle();
    await tapStudy(tester, 'Vista dividida');
    expect(find.byType(EditorScreen), findsNWidgets(2));
    await captureUi(tester, find.byKey(preview), 'study-split-v051');
    await tapStudy(tester, 'Cerrar espacio de trabajo');
    await waitStudy(
      tester,
      () => find.byType(LibraryScreen).evaluate().isNotEmpty,
    );
    final saved = (await services.repository.list())
        .firstWhere((e) => e.notebook.id == first.notebook.id)
        .notebook;
    expect(saved.pages.first.objects, hasLength(2));
    expect(saved.pages.first.strokes.single.points, hasLength(5));
    expect(saved.studyCards.single.repetitions, 1);
    expect(
      (await services.repository.list()).any(
        (e) => e.notebook.id == second.notebook.id,
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await services.close();
    await root.delete(recursive: true);
  });
}
