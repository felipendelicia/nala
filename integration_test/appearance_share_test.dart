import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:apuntes/app.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:apuntes/pdf/pdf_share.dart';
import 'package:apuntes/pdf/document_files.dart';
import 'package:apuntes/ui/appearance.dart';
import 'support/capture.dart';

class SharedPdf implements PdfShare {
  Uint8List? bytes;
  @override
  List<ShareTarget> get targets => [ShareTarget.system];
  @override
  Future<bool> share(
    Uint8List bytes, {
    required String name,
    ShareTarget target = ShareTarget.system,
  }) async {
    this.bytes = bytes;
    return true;
  }
}

class NoSaveFiles implements DocumentFiles {
  int saves = 0;
  @override
  Future<SelectedPdf?> openPdf() async => null;
  @override
  Future<bool> savePdf(Uint8List bytes, {required String name}) async {
    saves++;
    return true;
  }
}

Future<void> until(WidgetTester tester, bool Function() ready) async {
  final timer = Stopwatch()..start();
  while (!ready()) {
    if (timer.elapsed > const Duration(seconds: 40)) {
      fail('La operación no terminó.');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'tema oscuro, página continua, compartir y mover desde la biblioteca',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'nala-appearance-share-',
      );
      final shared = SharedPdf(), files = NoSaveFiles();
      final services = await AppServices.open(
        root.path,
        files: files,
        share: shared,
      );
      final folder = await services.library.createFolder('Universidad');
      final note = Notebook.blank(
        id: 'analysis',
        pageId: 'p0',
        title: 'Análisis I',
        subject: 'Universidad',
        pattern: PaperPattern.grid,
        now: DateTime.now(),
      );
      await services.library.add(
        note.copyWith(
          pages: [
            note.pages.first,
            NotebookPage(
              id: 'p1',
              width: 595.28,
              height: 841.89,
              background: const PageBackground.paper(PaperPattern.grid),
            ),
            NotebookPage(
              id: 'p2',
              width: 595.28,
              height: 841.89,
              background: const PageBackground.paper(PaperPattern.grid),
            ),
          ],
        ),
      );
      await services.library.add(
        Notebook.blank(
          id: 'physics',
          pageId: 'p3',
          title: 'Física — Guía de ejercicios',
          subject: 'Física',
          pattern: PaperPattern.ruled,
          now: DateTime.now(),
        ),
      );
      const preview = ValueKey('appearance-preview');
      await tester.pumpWidget(
        RepaintBoundary(
          key: preview,
          child: NalaApp(services: services),
        ),
      );
      await until(
        tester,
        () => find.byType(LibraryScreen).evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Apariencia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Claro'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(LibraryScreen))).brightness,
        Brightness.light,
      );
      await captureUi(tester, find.byKey(preview), 'library-light-v03');
      await tester.tap(find.byTooltip('Apariencia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oscuro'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(LibraryScreen))).brightness,
        Brightness.dark,
      );
      await captureUi(tester, find.byKey(preview), 'library-dark-v03');
      await tester.tap(find.text('Análisis I'));
      await until(
        tester,
        () => find.byType(EditorScreen).evaluate().isNotEmpty,
      );
      await captureUi(tester, find.byKey(preview), 'editor-dark-v03');
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(
            find.byKey(const ValueKey('document-viewport')),
          ),
          scrollDelta: const Offset(0, 550),
        ),
      );
      await tester.pumpAndSettle();
      final second = find.byKey(const ValueKey('canvas-p1'));
      expect(second, findsOneWidget);
      final canvas = tester.renderObject<RenderBox>(second);
      final pen = await tester.startGesture(
        canvas.localToGlobal(const Offset(100, 130)),
        kind: PointerDeviceKind.stylus,
      );
      await pen.moveBy(const Offset(80, 25));
      await pen.up();
      await tester.pumpAndSettle();
      await captureUi(tester, find.byKey(preview), 'continuous-dark-v03');
      await tester.tap(find.byTooltip('Compartir PDF'));
      await until(tester, () => shared.bytes != null);
      expect(files.saves, 0);
      final output = await PdfDocument.openData(shared.bytes!);
      expect(output.pages, hasLength(3));
      await output.dispose();
      await tester.tap(find.byTooltip('Modo lectura'));
      await tester.tap(find.byTooltip('Bloquear zoom'));
      await tester.tap(find.byTooltip('Bloquear movimiento horizontal'));
      await tester.pumpAndSettle();
      await captureUi(tester, find.byKey(preview), 'reading-dark-v03');
      await tester.tap(find.byTooltip('Volver a mis apuntes'));
      await until(tester, () => find.byType(EditorScreen).evaluate().isEmpty);
      final tile = find
          .ancestor(of: find.text('Análisis I'), matching: find.byType(InkWell))
          .first;
      await tester.tap(
        find.descendant(
          of: tile,
          matching: find.byTooltip('Opciones de apunte'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mover a…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Universidad').last);
      await until(
        tester,
        () =>
            services.library.entries
                .firstWhere((e) => e.notebook.id == 'analysis')
                .notebook
                .folderId ==
            folder.id,
      );
      expect(find.text('Análisis I'), findsNothing);
      final settings = await AppearanceController.open(root.path);
      expect(settings.mode, ThemeMode.dark);
      settings.dispose();
      // Verify the native bridge exists without altering the user's clipboard.
      await expectLater(
        const MethodChannel(
          'nala/share',
        ).invokeMethod<bool>('copyPdf', {'path': '${root.path}/missing.pdf'}),
        throwsA(isA<PlatformException>()),
      );
      await tester.pumpWidget(const SizedBox());
      await services.close();
      final reopened = await AppServices.open(root.path);
      final stored = reopened.library.entries
          .firstWhere((e) => e.notebook.id == 'analysis')
          .notebook;
      expect(stored.folderId, folder.id);
      expect(stored.pages[0].strokes, isEmpty);
      expect(stored.pages[1].strokes, hasLength(1));
      await reopened.close();
      await root.delete(recursive: true);
    },
  );
}
