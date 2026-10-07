import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/pdf/document_files.dart';
import 'package:apuntes/pdf/pdf_service.dart';
import 'package:apuntes/pdf/pdf_share.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';
import '../support/pdf_fixtures.dart';
import '../support/pdf_engine.dart';

class Files implements DocumentFiles {
  int saves = 0;
  @override
  Future<SelectedPdf?> openPdf() async => null;
  @override
  Future<bool> savePdf(Uint8List bytes, {required String name}) async {
    saves++;
    return true;
  }
}

class Share implements PdfShare {
  Uint8List? bytes;
  String? title;
  bool fail = false;
  int calls = 0;
  @override
  List<ShareTarget> get targets => [ShareTarget.system];
  @override
  Future<bool> share(
    Uint8List data, {
    required String name,
    ShareTarget target = ShareTarget.system,
  }) async {
    calls++;
    if (fail) throw const FileSystemException('unavailable');
    bytes = data;
    title = name;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'compartir crea archivos únicos seguros y limpia sólo sesiones antiguas',
    () async {
      final root = await Directory.systemTemp.createTemp('nala-share-test-');
      addTearDown(() => root.delete(recursive: true));
      final old = await Directory(
        '${root.path}/nala-share/old',
      ).create(recursive: true);
      final oldFile = await File('${old.path}/Old.pdf').writeAsBytes([1]);
      await oldFile.setLastModified(
        DateTime.now().subtract(const Duration(days: 3)),
      );
      final sibling = await File('${root.path}/other.pdf').writeAsBytes([9]);
      const channel = MethodChannel('nala/share');
      final received = <String>[];
      final source = await makeFixturePdf();
      testerMessenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'copyPdf');
        final path = (call.arguments as Map)['path'] as String;
        received.add(path);
        if (Platform.isLinux) {
          expect(
            (await File(path).stat()).mode & 0x3f,
            0,
            reason: 'El PDF temporal es privado.',
          );
          expect((await File(path).parent.stat()).mode & 0x3f, 0);
          expect((await File(path).parent.parent.stat()).mode & 0x3f, 0);
        }
        expect(await File(path).readAsBytes(), source);
        expect(File(path).parent.parent.path, '${root.path}/nala-share');
        expect(File(path).uri.pathSegments.last.length, lessThan(180));
        return true;
      });
      addTearDown(
        () => testerMessenger.setMockMethodCallHandler(channel, null),
      );
      final service = NativePdfShare(temporaryDirectory: () async => root);
      await service.share(
        source,
        name: '../../Álgebra.pdf',
        target: ShareTarget.copyFile,
      );
      await service.share(
        source,
        name: '../../Álgebra.pdf',
        target: ShareTarget.copyFile,
      );
      expect(received.toSet(), hasLength(2));
      for (final path in received) {
        expect(await File(path).exists(), isTrue);
      }
      expect(await old.exists(), isFalse);
      expect(await sibling.exists(), isTrue);
    },
  );
  testWidgets(
    'Compartir PDF prepara una instantánea sin selector de guardado',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('nala-share-editor-'),
      ))!;
      final pdf = PdfService(
        assets: FileAssetStore('${root.path}/assets'),
        initialize: () => initializePdfForTest(root.path),
      );
      final share = Share(), files = Files();
      var id = 0;
      final controller = EditorController(
        notebook: fixtureNotebook(),
        repository: MemoryRepository(),
        deviceId: 'pc',
        newId: () => 'r${++id}',
        now: () => DateTime.utc(2026),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EditorScreen(
            controller: controller,
            pdf: pdf,
            files: files,
            share: share,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Compartir PDF'));
      await tester.tap(find.byTooltip('Compartir PDF'));
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (share.bytes == null && DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(share.bytes, isNotNull);
      await tester.pumpAndSettle();
      expect(files.saves, 0);
      expect(share.calls, 1);
      expect(share.title, 'Álgebra');
      final document = await tester.runAsync(
        () => PdfDocument.openData(share.bytes!),
      );
      expect(document!.pages, hasLength(1));
      await tester.runAsync(document.dispose);
      share.fail = true;
      await tester.tap(find.byTooltip('Compartir PDF'));
      final retryDeadline = DateTime.now().add(const Duration(seconds: 10));
      while (share.calls < 2 && DateTime.now().isBefore(retryDeadline)) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('No se pudo compartir'), findsOneWidget);
      expect(controller.notebook.pages.single.strokes, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      pdf.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
}

final testerMessenger =
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
