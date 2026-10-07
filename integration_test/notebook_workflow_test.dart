import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:apuntes/app.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/backup/backup_dialog.dart';
import 'package:apuntes/backup/backup_files.dart';
import 'package:apuntes/backup/backup_service.dart';
import 'package:apuntes/backup/backup_zip.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/page_object.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:apuntes/editor/toolbar_preferences.dart';
import 'package:apuntes/elements/element_store.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:apuntes/pdf/pdf_export_service.dart';
import 'support/capture.dart';

Future<void> waitWorkflow(
  WidgetTester tester,
  bool Function() ready, {
  String operation = 'la operación',
}) async {
  final watch = Stopwatch()..start();
  while (!ready()) {
    if (watch.elapsed.inSeconds >= 60) {
      fail('No terminó $operation.');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> tapWorkflow(WidgetTester tester, String label) async {
  final notebookOption = {
    'Abrir otro apunte',
    'Vista dividida',
    'Exportar PDF',
  }.contains(label);
  var target = find.byTooltip(label).hitTestable();
  if (target.evaluate().isEmpty) {
    await tester.tap(
      find
          .byTooltip(
            notebookOption ? 'Opciones del cuaderno' : 'Más herramientas',
          )
          .first,
    );
    await tester.pumpAndSettle();
    target = notebookOption ? find.text(label) : find.byTooltip(label);
    final inDialog = find.descendant(of: find.byType(Dialog), matching: target);
    if (inDialog.evaluate().isNotEmpty) {
      target = inDialog;
    }
  }
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

EditorScreen activeWorkflowEditor(WidgetTester tester) => tester
    .widgetList<EditorScreen>(find.byType(EditorScreen))
    .firstWhere((editor) => editor.active);

Future<void> selectWorkflowObject(
  WidgetTester tester,
  NotebookPage page,
  PageObject object,
) async {
  await tapWorkflow(tester, 'Selección');
  final canvas = tester.renderObject<RenderBox>(
    find.byKey(ValueKey('canvas-${page.id}')),
  );
  final gesture = await tester.startGesture(
    canvas.localToGlobal(
      Offset(object.x + object.width / 2, object.y + object.height / 2),
    ),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> moveWorkflowSelection(
  WidgetTester tester,
  NotebookPage page,
  PageObject object,
  Offset delta,
) async {
  final canvas = tester.renderObject<RenderBox>(
    find.byKey(ValueKey('canvas-${page.id}')),
  );
  final center = Offset(
    object.x + object.width / 2,
    object.y + object.height / 2,
  );
  final drag = await tester.startGesture(
    canvas.localToGlobal(center),
    kind: PointerDeviceKind.mouse,
  );
  await drag.moveTo(canvas.localToGlobal(center + delta));
  await drag.up();
  await tester.pumpAndSettle();
}

/// Only the OS chooser is replaced. Export, inspection, persistence and restore
/// use native SQLite, files, image rendering and the production backup service.
class WorkflowBackupFiles implements BackupFiles {
  WorkflowBackupFiles(this.path);
  final String path;
  Uint8List? saved;
  @override
  Future<bool> save(Uint8List bytes, {required String name}) async {
    await File(path).writeAsBytes(bytes, flush: true);
    saved = bytes;
    return true;
  }

  @override
  Future<SelectedBackup?> open() async => saved == null
      ? null
      : SelectedBackup(
          bytes: await File(path).readAsBytes(),
          name: 'Workflow.nala.zip',
        );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('elementos, enlaces, imagen, barra, backup y LaTeX nativos', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('nala-workflow-native-');
    var services = await AppServices.open(root.path);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await services.close();
      await root.delete(recursive: true);
    });
    final first = await services.library.createNotebook(
      title: 'Álgebra de trabajo',
      subject: 'Universidad',
      pattern: PaperPattern.blank,
    );
    final second = await services.library.createNotebook(
      title: 'Análisis de destino',
      subject: 'Universidad',
      pattern: PaperPattern.grid,
    );
    final pixels = img.Image(width: 180, height: 110);
    for (var y = 0; y < pixels.height; y++) {
      for (var x = 0; x < pixels.width; x++) {
        final gray = ((x ~/ 20 + y ~/ 20) % 2 == 0) ? 70 : 210;
        pixels.setPixelRgb(x, y, gray, gray, gray);
      }
    }
    final originalImage = await services.assets.put(img.encodePng(pixels));
    final imageObject = PageObject(
      id: 'workflow-image',
      kind: PageObjectKind.image,
      x: 60,
      y: 150,
      width: 180,
      height: 110,
      assetId: originalImage,
    );
    final sourcePage = first.notebook.pages.first.copyWith(
      objects: [
        PageObject(
          id: 'workflow-heading',
          kind: PageObjectKind.text,
          x: 60,
          y: 65,
          width: 380,
          height: 40,
          text: 'Integrales y diagramas',
        ),
        imageObject,
      ],
    );
    final targetPage = NotebookPage(
      id: 'workflow-target-page',
      width: 595.28,
      height: 841.89,
      background: const PageBackground.paper(PaperPattern.grid),
      objects: [
        PageObject(
          id: 'workflow-target-heading',
          kind: PageObjectKind.text,
          x: 60,
          y: 80,
          width: 360,
          height: 50,
          text: 'La página enlazada',
        ),
      ],
    );
    for (final entry in [
      (first, first.notebook.copyWith(pages: [sourcePage])),
      (
        second,
        second.notebook.copyWith(
          pages: [second.notebook.pages.first, targetPage],
        ),
      ),
    ]) {
      await services.repository.commit(
        Revision(
          id: 'seed-${entry.$1.notebook.id}',
          deviceId: services.deviceId,
          parentId: entry.$1.headId,
          createdAt: DateTime.now().toUtc(),
          notebook: entry.$2,
        ),
      );
    }
    await services.library.refresh();
    const preview = ValueKey('workflow-preview');
    Widget app() => RepaintBoundary(
      key: preview,
      child: NalaApp(services: services),
    );
    await tester.pumpWidget(app());
    await waitWorkflow(
      tester,
      () => find.byType(LibraryScreen).evaluate().isNotEmpty,
      operation: 'la biblioteca',
    );
    await tester.tap(find.text('Álgebra de trabajo'));
    await waitWorkflow(
      tester,
      () => find.byType(EditorScreen).evaluate().isNotEmpty,
      operation: 'el editor',
    );
    final source = activeWorkflowEditor(tester).controller;

    await tapWorkflow(tester, 'Insertar fórmula LaTeX');
    await tester.enterText(find.byType(TextField).first, r'\frac{');
    await tester.pumpAndSettle();
    expect(find.textContaining('Fórmula inválida'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Insertar'))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byType(TextField).first,
      r'\int_0^1 x^2\,dx = \frac{1}{3}',
    );
    await tester.pumpAndSettle();
    await captureUi(tester, find.byKey(preview), 'workflow-latex-v060');
    await tester.tap(find.widgetWithText(FilledButton, 'Insertar'));
    await waitWorkflow(
      tester,
      () => source.notebook.pages.first.objects.any(
        (object) => object.kind == PageObjectKind.latex,
      ),
      operation: 'la fórmula',
    );
    final firstFormula = source.notebook.pages.first.objects.singleWhere(
      (object) => object.kind == PageObjectKind.latex,
    );
    expect(await services.assets.contains(firstFormula.assetId!), isTrue);
    await tapWorkflow(tester, 'Editar fórmula');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      firstFormula.text,
    );
    const editedSource = r'\int_0^1 x^3\,dx = \frac{1}{4}';
    await tester.enterText(find.byType(TextField).first, editedSource);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await waitWorkflow(
      tester,
      () => source.notebook.pages.first.objects.any(
        (object) => object.text == editedSource,
      ),
      operation: 'la edición LaTeX',
    );
    final formula = source.notebook.pages.first.objects.singleWhere(
      (object) => object.kind == PageObjectKind.latex,
    );
    expect(formula.id, firstFormula.id);
    expect(formula.assetId, isNot(firstFormula.assetId));

    await tapWorkflow(tester, 'Guardar elemento');
    await tester.enterText(
      find.byType(TextField).first,
      'Integral reutilizable',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar elemento'));
    await waitWorkflow(
      tester,
      () => find.textContaining('Elemento guardado:').evaluate().isNotEmpty,
      operation: 'el elemento',
    );
    final store = ElementStore(root: root.path);
    final element = (await store.load()).single;
    expect(element.objects.single.text, editedSource);
    expect(element.assetIds, {formula.assetId});
    final objectCount = source.notebook.pages.first.objects.length;
    await tapWorkflow(tester, 'Elementos reutilizables');
    await waitWorkflow(
      tester,
      () => find.text('Integral reutilizable').evaluate().isNotEmpty,
    );
    await tester.enterText(find.byType(TextField).first, 'INTEGRAL');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Integral reutilizable'));
    await waitWorkflow(
      tester,
      () => source.notebook.pages.first.objects.length == objectCount + 1,
      operation: 'la inserción del elemento',
    );
    final inserted = source.notebook.pages.first.objects.last;
    expect(inserted.id, isNot(formula.id));
    expect(inserted.text, editedSource);
    expect(inserted.assetId, formula.assetId);
    expect(inserted.locked, isFalse);
    await moveWorkflowSelection(
      tester,
      source.notebook.pages.first,
      inserted,
      const Offset(0, 100),
    );
    expect(
      source.notebook.pages.first.objects.last.y,
      closeTo(inserted.y + 100, .001),
    );
    expect(
      source.notebook.pages.first.objects
          .singleWhere((object) => object.id == formula.id)
          .y,
      formula.y,
    );

    PageObject sourceImage() => source.notebook.pages.first.objects.singleWhere(
      (object) => object.id == imageObject.id,
    );
    await selectWorkflowObject(
      tester,
      source.notebook.pages.first,
      sourceImage(),
    );
    await tapWorkflow(tester, 'Editar imagen');
    final dialogImage = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(Image),
    );
    await waitWorkflow(
      tester,
      () =>
          dialogImage.evaluate().isNotEmpty &&
          tester.widget<Slider>(find.byType(Slider)).onChanged != null,
      operation: 'la imagen',
    );
    final imageRect = tester.getRect(dialogImage);
    await tester.dragFrom(
      imageRect.topLeft + Offset(imageRect.width * .1, imageRect.height * .1),
      Offset(imageRect.width * .6, imageRect.height * .65),
    );
    final slider = tester.getRect(find.byType(Slider));
    await tester.tapAt(
      Offset(slider.left + slider.width * .45, slider.center.dy),
    );
    await tester.pumpAndSettle();
    await captureUi(tester, find.byKey(preview), 'workflow-image-v060');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await waitWorkflow(
      tester,
      () => sourceImage().assetId != originalImage,
      operation: 'el recorte',
    );
    final cropped = sourceImage();
    expect(cropped.originalAssetId, originalImage);
    expect(cropped.opacity, closeTo(.45, .1));
    expect(cropped.width, lessThan(180));
    expect(cropped.height, lessThan(110));
    expect(
      img.decodePng(await services.assets.read(originalImage))!.width,
      180,
    );
    await tapWorkflow(tester, 'Editar imagen');
    await waitWorkflow(
      tester,
      () =>
          find.text('Restablecer original').evaluate().isNotEmpty &&
          tester.widget<Slider>(find.byType(Slider)).onChanged != null,
    );
    await tester.tap(find.text('Restablecer original'));
    await waitWorkflow(
      tester,
      () =>
          find.text('Restablecer original').evaluate().isEmpty &&
          tester.widget<Slider>(find.byType(Slider)).onChanged != null,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await waitWorkflow(
      tester,
      () => sourceImage().assetId == originalImage,
      operation: 'la imagen original',
    );
    expect(sourceImage().width, closeTo(180, .001));
    expect(sourceImage().height, closeTo(110, .001));
    expect(sourceImage().opacity, cropped.opacity);
    await tapWorkflow(tester, 'Bloquear objetos');
    await waitWorkflow(
      tester,
      () => sourceImage().locked,
      operation: 'el bloqueo',
    );
    final lockedX = sourceImage().x;
    await selectWorkflowObject(
      tester,
      source.notebook.pages.first,
      sourceImage(),
    );
    final canvas = tester.renderObject<RenderBox>(
      find.byKey(ValueKey('canvas-${sourcePage.id}')),
    );
    final lockedGesture = await tester.startGesture(
      canvas.localToGlobal(Offset(sourceImage().x + 50, sourceImage().y + 50)),
      kind: PointerDeviceKind.mouse,
    );
    await lockedGesture.moveBy(const Offset(35, 20));
    await lockedGesture.up();
    await tester.pumpAndSettle();
    expect(sourceImage().x, lockedX);
    expect(sourceImage().locked, isTrue);
    await tapWorkflow(tester, 'Desbloquear objetos');
    await waitWorkflow(
      tester,
      () => !sourceImage().locked,
      operation: 'el desbloqueo',
    );

    await tapWorkflow(tester, 'Abrir otro apunte');
    await tester.tap(find.text('Análisis de destino').last);
    await waitWorkflow(
      tester,
      () =>
          activeWorkflowEditor(tester).controller.notebook.id ==
          second.notebook.id,
      operation: 'el segundo apunte',
    );
    final destination = activeWorkflowEditor(tester).controller;
    final destinationCanvas = tester.renderObject<RenderBox>(
      find.byType(PaperCanvas).first,
    );
    final pen = await tester.startGesture(
      destinationCanvas.localToGlobal(const Offset(80, 180)),
      kind: PointerDeviceKind.stylus,
    );
    await pen.moveTo(destinationCanvas.localToGlobal(const Offset(180, 200)));
    await pen.up();
    await tester.pumpAndSettle();
    expect(destination.notebook.pages.first.strokes, hasLength(1));
    final keptStroke = destination.notebook.pages.first.strokes.single.id;
    await tester.tap(
      find.byKey(ValueKey('workspace-tab-${first.notebook.id}')),
    );
    await waitWorkflow(
      tester,
      () => activeWorkflowEditor(tester).controller == source,
    );
    await selectWorkflowObject(
      tester,
      source.notebook.pages.first,
      sourceImage(),
    );
    await tapWorkflow(tester, 'Enlazar selección');
    await waitWorkflow(
      tester,
      () => find.text('Página 2').evaluate().isNotEmpty,
    );
    await tester.enterText(find.byType(TextField).first, 'Análisis');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Página 2'));
    await waitWorkflow(
      tester,
      () => sourceImage().link != null,
      operation: 'el enlace de imagen',
    );
    expect(sourceImage().link!.pageId, targetPage.id);
    await tapWorkflow(tester, 'Enlace a otro apunte');
    await waitWorkflow(
      tester,
      () => find.text('Página 2').evaluate().isNotEmpty,
    );
    await tester.enterText(find.byType(TextField).first, 'Análisis');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Página 2'));
    await waitWorkflow(
      tester,
      () => source.notebook.pages.first.objects.last.link != null,
    );
    expect(
      source.notebook.pages.first.objects.last.text,
      'Análisis de destino · Página 2',
    );
    await moveWorkflowSelection(
      tester,
      source.notebook.pages.first,
      source.notebook.pages.first.objects.last,
      const Offset(-200, -100),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await captureUi(tester, find.byKey(preview), 'workflow-editor-v060');
    await tapWorkflow(tester, 'Abrir enlace');
    await waitWorkflow(
      tester,
      () => find.text('2/2').evaluate().isNotEmpty,
      operation: 'la página ya abierta',
    );
    expect(
      identical(activeWorkflowEditor(tester).controller, destination),
      isTrue,
    );
    expect(destination.notebook.pages.first.strokes.single.id, keptStroke);

    await tapWorkflow(tester, 'Personalizar barra');
    await tester.tap(find.byType(DropdownButtonFormField<ToolbarDock>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Izquierda').last);
    await tester.pumpAndSettle();
    final handles = find.byType(ReorderableDragStartListener);
    final firstHandle = tester.getCenter(handles.at(0));
    final secondHandle = tester.getCenter(handles.at(1));
    debugPrint('Workflow toolbar handles: $firstHandle -> $secondHandle');
    await captureUi(
      tester,
      find.byKey(preview),
      'workflow-toolbar-settings-v060',
    );
    final reorder = await tester.startGesture(
      firstHandle,
      kind: PointerDeviceKind.mouse,
    );
    await reorder.moveBy(const Offset(0, 4));
    await tester.pump(const Duration(milliseconds: 100));
    await reorder.moveTo(
      firstHandle + Offset(0, (secondHandle.dy - firstHandle.dy) * .75),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await reorder.moveTo(secondHandle + const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 500));
    await reorder.up();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Lápiz'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await waitWorkflow(
      tester,
      () => services.toolbarPreferences!.layout.dock == ToolbarDock.left,
    );
    expect(
      services.toolbarPreferences!.layout.order.first,
      ToolbarAction.highlighter,
    );
    expect(
      services.toolbarPreferences!.layout.visible,
      isNot(contains(ToolbarAction.pen)),
    );
    await captureUi(tester, find.byKey(preview), 'workflow-toolbar-v060');
    await source.flush();
    await destination.flush();
    final pdf = await PdfExportService(services.pdf).export(source.notebook);
    expect(pdf.sublist(0, 5), '%PDF-'.codeUnits);
    await File('.dart_tool/ui-qa/workflow-export-v060.pdf').writeAsBytes(pdf);
    await tapWorkflow(tester, 'Cerrar espacio de trabajo');
    await waitWorkflow(
      tester,
      () => find.byType(LibraryScreen).evaluate().isNotEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await services.close();
    services = await AppServices.open(root.path);
    final reopened = await services.repository.load(first.notebook.id);
    expect(
      reopened!.pages.first.objects
          .where((o) => o.kind == PageObjectKind.latex)
          .map((o) => o.text),
      [editedSource, editedSource],
    );
    expect(services.toolbarPreferences!.layout.dock, ToolbarDock.left);
    expect(
      services.toolbarPreferences!.layout.order.first,
      ToolbarAction.highlighter,
    );
    expect(
      (await ElementStore(root: root.path).load()).single.name,
      'Integral reutilizable',
    );
    await tester.pumpWidget(app());
    await waitWorkflow(
      tester,
      () => find.byType(LibraryScreen).evaluate().isNotEmpty,
    );

    final backup = BackupService(
      root: root.path,
      repository: services.repository,
      assets: services.assets,
      deviceId: services.deviceId,
    );
    final files = WorkflowBackupFiles(
      '.dart_tool/ui-qa/workflow-v060.nala.zip',
    );
    BackupRestoreResult? restored;
    final dialog = showBackupDialog(
      tester.element(find.byType(LibraryScreen)),
      service: backup,
      files: files,
      onRestored: (result) async {
        restored = result;
        await services.library.refresh();
        await services.toolbarPreferences!.reload();
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar backup'));
    await waitWorkflow(
      tester,
      () => find.text('Backup guardado.').evaluate().isNotEmpty,
      operation: 'el backup nativo',
    );
    final checked = await backup.inspect(files.saved!);
    expect(checked.notebookCount, 2);
    expect(checked.elementCount, 1);
    // Local commits coalesce unfrozen revisions. The reset image uses its
    // original asset, and both formulas and the element share the edited PNG.
    final expectedAssets = {originalImage, formula.assetId!};
    final archivedFiles = readBackupZip(files.saved!);
    expect(checked.assetCount, expectedAssets.length);
    expect(
      archivedFiles.keys.where((name) => name.startsWith('assets/')),
      unorderedEquals(expectedAssets.map((id) => 'assets/$id')),
    );
    for (final assetId in expectedAssets) {
      expect(
        archivedFiles['assets/$assetId'],
        orderedEquals(await services.assets.read(assetId)),
      );
    }
    await tester.tap(find.text('Abrir backup'));
    await waitWorkflow(
      tester,
      () => find.text('Recuperar copias').evaluate().isNotEmpty,
    );
    expect(
      find.textContaining('conserva los apuntes actuales'),
      findsOneWidget,
    );
    await captureUi(
      tester,
      find.byKey(preview),
      'workflow-backup-preview-v060',
    );
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recuperar copias'));
    await waitWorkflow(
      tester,
      () => find.text('Abrir carpeta recuperada').evaluate().isNotEmpty,
      operation: 'la recuperación',
    );
    expect(restored!.notebookCount, 2);
    expect(restored!.elementCount, 1);
    expect(restored!.preferencesRestored, isTrue);
    final entries = await services.repository.list();
    expect(entries, hasLength(4));
    expect(await services.repository.load(first.notebook.id), isNotNull);
    final recoveredSource = entries
        .singleWhere(
          (entry) =>
              entry.notebook.id != first.notebook.id &&
              entry.notebook.title == 'Álgebra de trabajo',
        )
        .notebook;
    final recoveredTarget = entries
        .singleWhere(
          (entry) =>
              entry.notebook.id != second.notebook.id &&
              entry.notebook.title == 'Análisis de destino',
        )
        .notebook;
    final restoredLink = recoveredSource.pages.first.objects.last.link!;
    expect(restoredLink.notebookId, recoveredTarget.id);
    expect(restoredLink.pageId, recoveredTarget.pages[1].id);
    final recoveredFormulas = recoveredSource.pages.first.objects.where(
      (object) => object.kind == PageObjectKind.latex,
    );
    expect(recoveredFormulas.map((object) => object.text), [
      editedSource,
      editedSource,
    ]);
    expect(recoveredFormulas.map((object) => object.assetId), [
      formula.assetId,
      formula.assetId,
    ]);
    expect(
      recoveredSource.pages.first.objects
          .singleWhere((object) => object.kind == PageObjectKind.image)
          .assetId,
      originalImage,
    );
    expect((await ElementStore(root: root.path).load()), hasLength(2));
    await tester.tap(find.text('Abrir carpeta recuperada'));
    await tester.pumpAndSettle();
    expect((await dialog)!.notebookCount, 2);
    expect(tester.takeException(), isNull);
  });
}
