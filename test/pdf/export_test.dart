import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/deferred_notebook_page.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/page_comment.dart';
import 'package:apuntes/editor/markdown_sheet.dart';
import 'package:apuntes/pdf/pdf_service.dart';
import 'package:apuntes/pdf/pdf_export_service.dart';
import '../support/pdf_engine.dart';
import '../support/pdf_fixtures.dart';

class _TrackedDeferredPage extends DeferredNotebookPage {
  _TrackedDeferredPage(NotebookPage page)
    : super(
        id: page.id,
        width: page.width,
        height: page.height,
        background: page.background,
        encoded: jsonEncode(page.toJson()),
      );

  @override
  NotebookPage materialize() {
    if (!isReady) NotebookCodec.reportWork('decode-deferred-page');
    return super.materialize();
  }
}

void main() {
  test(
    'exportar Markdown guardado conserva las hojas originales y el texto completo',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'nala-export-markdown-',
      );
      final pdf = PdfService(
        assets: FileAssetStore('${dir.path}/assets'),
        initialize: () => initializePdfForTest(dir.path),
      );
      addTearDown(() async {
        pdf.dispose();
        await dir.delete(recursive: true);
      });
      var id = 0;
      String newId() => 'hoja-${++id}';
      final book = await pdf.importDocument(
        bytes: await makeFixturePdf(),
        documentId: 'study',
        title: 'Álgebra',
        newId: newId,
        now: DateTime.utc(2026),
      );
      const paragraph =
          'Conviene distinguir el **vector** de sus componentes. ';
      final markdown =
          '# Resumen de álgebra\n\n'
          '${List.filled(24, paragraph * 5).join('\n\n')}\n\nÚltima conclusión.';
      final saved = NotebookPage.fromJson({
        'id': newId(),
        'width': markdownSheetWidth,
        'height': markdownSheetHeight,
        'background': {'kind': 'paper', 'pattern': 'blank'},
        'strokes': <Map<String, dynamic>>[],
        'markdown': '# Resumen de álgebra',
      });
      final edited = updateMarkdownSheets(saved, markdown, newId: newId);
      expect(edited.length, greaterThan(1));
      final bytes = await PdfExportService(
        pdf,
      ).export(book.copyWith(pages: [...book.pages, ...edited]));
      final document = await PdfDocument.openData(bytes);
      try {
        expect(document.pages, hasLength(2 + edited.length));
        expect(document.pages[0].width, closeTo(595.28, .01));
        expect(document.pages[0].height, closeTo(841.89, .01));
        expect(document.pages[1].width, closeTo(841.89, .01));
        expect(document.pages[1].height, closeTo(595.28, .01));
        final text = <String>[];
        for (final page in document.pages.skip(2)) {
          expect(page.width, closeTo(595.28, .01));
          expect(page.height, closeTo(841.89, .01));
          final content = (await page.loadText())!;
          expect(content.fullText, isNotEmpty);
          final outside = content.charRects.where(
            (rect) =>
                rect.isNotEmpty &&
                (rect.left < 0 ||
                    rect.right > page.width ||
                    rect.bottom < 0 ||
                    rect.top > page.height),
          );
          expect(outside, isEmpty);
          text.add(content.fullText);
        }
        expect(text.first, contains('Resumen de álgebra'));
        expect(text.last, contains('Última conclusión.'));
        expect('vector'.allMatches(text.join('\n')), hasLength(120));
      } finally {
        await document.dispose();
      }
    },
  );

  test(
    'exportar tinta diferida la decodifica y compone fuera del hilo de escritura',
    () async {
      final dir = await Directory.systemTemp.createTemp('nala-export-worker-');
      final pdf = PdfService(
        assets: FileAssetStore('${dir.path}/assets'),
        initialize: () => initializePdfForTest(dir.path),
      );
      final receive = ReceivePort(), events = <(String, SendPort)>[];
      final sub = receive.listen(
        (event) => events.add(event as (String, SendPort)),
      );
      NotebookCodec.diagnostics = receive.sendPort;
      try {
        final book = Notebook.blank(
          id: 'large',
          pageId: 'page',
          title: 'Tinta',
          subject: '',
          pattern: PaperPattern.blank,
          now: DateTime.utc(2026),
        );
        final page = book.pages.first.copyWith(
          strokes: [
            InkStroke(
              id: 'long',
              tool: InkTool.pen,
              argb: 0xff202020,
              width: 2,
              points: List.generate(
                5000,
                (i) => InkPoint(
                  x: 20 + i % 500 * 1.0,
                  y: 20 + i ~/ 500 * 1.0,
                  pressure: .5,
                ),
              ),
            ),
          ],
        );
        final bytes = await PdfExportService(
          pdf,
          codecEvents: receive.sendPort,
        ).export(book.copyWith(pages: [_TrackedDeferredPage(page)]));
        final document = await PdfDocument.openData(bytes);
        expect(document.pages, hasLength(1));
        await document.dispose();
        await Future<void>.delayed(Duration.zero);
        expect(events, isNotEmpty);
        expect(
          events.every((event) => event.$2 != Isolate.current.controlPort),
          isTrue,
        );
      } finally {
        NotebookCodec.diagnostics = null;
        await sub.cancel();
        receive.close();
        pdf.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'PDF conserva marcadores y un anexo de comentarios, incluida la voz',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'nala-export-comments-',
      );
      final pdf = PdfService(
        assets: FileAssetStore('${dir.path}/assets'),
        initialize: () => initializePdfForTest(dir.path),
      );
      try {
        final book = Notebook.blank(
          id: 'comments',
          pageId: 'page',
          title: 'Clase',
          subject: '',
          pattern: PaperPattern.blank,
          now: DateTime.utc(2026),
        );
        final comments = [
          PageComment(
            id: 'text',
            x: 100,
            y: 100,
            text: 'Revisar demostración y λ',
            createdAt: DateTime.utc(2026),
          ),
          PageComment(
            id: 'voice',
            x: 200,
            y: 200,
            text: '',
            createdAt: DateTime.utc(2026),
            audioAssetId: 'a' * 64,
            audioDurationMs: 3000,
          ),
        ];
        final bytes = await PdfExportService(pdf).export(
          book.copyWith(
            pages: [
              book.pages.first.copyWith(
                comments: comments,
                strokes: [
                  InkStroke(
                    id: 'marker-underlay',
                    tool: InkTool.highlighter,
                    argb: 0xff000000,
                    width: 30,
                    points: const [InkPoint(x: 100, y: 100, pressure: 1)],
                  ),
                ],
              ),
            ],
          ),
        );
        final document = await PdfDocument.openData(bytes);
        try {
          expect(document.pages, hasLength(2));
          await Directory('.dart_tool/pdf-qa').create(recursive: true);
          await File('.dart_tool/pdf-qa/comments.pdf').writeAsBytes(bytes);
          expect(
            (await document.pages.first.loadText())!.fullText,
            contains('1'),
          );
          final image = (await document.pages.first.render(
            backgroundColor: 0xffffffff,
          ))!;
          try {
            final offset = (104 * image.width + 94) * 4;
            expect(image.pixels.sublist(offset, offset + 3), [75, 88, 36]);
          } finally {
            image.dispose();
          }
          final text = (await document.pages.last.loadText())!.fullText;
          expect(text, contains('Revisar demostración y λ'));
          expect(text, contains('Nota de voz'));
          expect(text, contains('Audio disponible en Nala'));
        } finally {
          await document.dispose();
        }
      } finally {
        pdf.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'exportar desbloquea el recurso correcto y reintenta la misma instantánea',
    () async {
      final dir = await Directory.systemTemp.createTemp('nala-export-locked-');
      final assets = FileAssetStore('${dir.path}/assets');
      final pdf = PdfService(
        assets: assets,
        initialize: () => initializePdfForTest(dir.path),
      );
      addTearDown(() async {
        pdf.dispose();
        await dir.delete(recursive: true);
      });
      var id = 0;
      final ordinary = await pdf.importDocument(
        bytes: await makeFixturePdf(),
        title: 'Guía',
        documentId: 'guide',
        newId: () => 'p${++id}',
        now: DateTime.utc(2026),
      );
      final protected = await pdf.importDocument(
        bytes: await File('test/support/pdf/protected.pdf').readAsBytes(),
        password: 'nala-test',
        title: 'Protegido',
        documentId: 'protected',
        newId: () => 'p${++id}',
        now: DateTime.utc(2026),
      );
      final reopened = PdfService(
        assets: assets,
        initialize: () => initializePdfForTest(dir.path),
      );
      addTearDown(reopened.dispose);
      final snapshot = ordinary.copyWith(
        pages: [ordinary.pages.first, protected.pages.first],
      );
      final asked = <String>[];
      final output = await PdfExportService(reopened).exportWithUnlock(
        snapshot,
        (assetId) async {
          asked.add(assetId);
          await reopened.unlock(assetId, 'nala-test');
          return true;
        },
      );
      expect(asked, [protected.pages.first.background.assetId]);
      final document = await PdfDocument.openData(output!);
      expect(document.pages, hasLength(2));
      await document.dispose();
      final cancelled = PdfService(
        assets: assets,
        initialize: () => initializePdfForTest(dir.path),
      );
      addTearDown(cancelled.dispose);
      expect(
        await PdfExportService(
          cancelled,
        ).exportWithUnlock(snapshot, (_) async => false),
        isNull,
      );
    },
  );
  test(
    'exportar páginas mixtas conserva orden, tamaño, tinta y transparencia',
    () async {
      final dir = await Directory.systemTemp.createTemp('nala-export-');
      final assets = FileAssetStore('${dir.path}/assets');
      final service = PdfService(
        assets: assets,
        initialize: () => initializePdfForTest(dir.path),
      );
      addTearDown(() async {
        service.dispose();
        await dir.delete(recursive: true);
      });
      var id = 0;
      var note = await service.importDocument(
        bytes: await makeFixturePdf(),
        title: 'Guía',
        documentId: 'guide',
        newId: () => 'id-${++id}',
        now: DateTime.utc(2026, 10, 6),
      );
      InkStroke dot(
        String id,
        double x,
        double y,
        int color, {
        InkTool tool = InkTool.pen,
      }) => InkStroke(
        id: id,
        tool: tool,
        argb: color,
        width: 8,
        points: [InkPoint(x: x, y: y, pressure: 1)],
      );
      note = note.copyWith(
        pages: [
          note.pages[0].copyWith(
            strokes: [
              dot('red', 32, 32, 0xffff0000),
              InkStroke(
                id: 'highlight',
                tool: InkTool.highlighter,
                argb: 0xffffff00,
                width: 8,
                points: [
                  const InkPoint(x: 12, y: 16, pressure: .25),
                  const InkPoint(x: 16, y: 16, pressure: .75),
                  const InkPoint(x: 20, y: 16, pressure: 1),
                  // The same compound fill spans more than one PDF stream.
                  for (var i = 0; i < 1100; i++)
                    const InkPoint(x: 16, y: 16, pressure: .5),
                  const InkPoint(x: 26, y: 16, pressure: 1),
                ],
              ),
            ],
          ),
          NotebookPage(
            id: 'blank',
            width: 200,
            height: 300,
            background: const PageBackground.paper(PaperPattern.grid),
            strokes: [
              dot('black', 32, 32, 0xff000000),
              dot('translucent', 48, 48, 0x800000ff),
            ],
          ),
          note.pages[1].copyWith(strokes: [dot('blue', 811, 565, 0xff0000ff)]),
        ],
      );
      final result = await PdfExportService(service).export(note);
      final output = await PdfDocument.openData(result);
      try {
        expect(output.pages, hasLength(3));
        expect(output.pages[0].width, closeTo(595.28, .01));
        expect(output.pages[0].height, closeTo(841.89, .01));
        expect(output.pages[1].width, closeTo(200, .01));
        expect(output.pages[1].height, closeTo(300, .01));
        expect(output.pages[2].width, closeTo(841.89, .01));
        expect(output.pages[2].height, closeTo(595.28, .01));
        Future<List<int>> pixel(int page, int x, int y) async {
          final image = (await output.pages[page].render(
            backgroundColor: 0xffffffff,
          ))!;
          try {
            final offset = (y * image.width + x) * 4;
            return [
              image.pixels[offset + 2],
              image.pixels[offset + 1],
              image.pixels[offset],
            ];
          } finally {
            image.dispose();
          }
        }

        expect(await pixel(0, 32, 32), [255, 0, 0]);
        final mixed = await pixel(0, 16, 16);
        expect(mixed[0], greaterThan(240));
        expect(mixed[1], inInclusiveRange(70, 110));
        expect(mixed[2], lessThan(30));
        expect((await pixel(0, 13, 16))[1], inInclusiveRange(70, 110));
        expect((await pixel(0, 25, 16))[2], inInclusiveRange(155, 180));
        expect(await pixel(1, 32, 32), [0, 0, 0]);
        expect(await pixel(1, 48, 48), [
          inInclusiveRange(127, 128),
          inInclusiveRange(127, 128),
          255,
        ]);
        expect(await pixel(2, 811, 565), [0, 0, 255]);
        final qa = Directory('.dart_tool/pdf-qa');
        await qa.create(recursive: true);
        await File('${qa.path}/roundtrip.pdf').writeAsBytes(result);
      } finally {
        await output.dispose();
      }
    },
  );
}
