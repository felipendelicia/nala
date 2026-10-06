import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/pdf/pdf_service.dart';
import 'package:apuntes/pdf/pdf_export_service.dart';
import '../support/pdf_engine.dart';
import '../support/pdf_fixtures.dart';

void main() {
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
              dot('highlight', 16, 16, 0xffffff00, tool: InkTool.highlighter),
            ],
          ),
          NotebookPage(
            id: 'blank',
            width: 200,
            height: 300,
            background: const PageBackground.paper(PaperPattern.grid),
            strokes: [dot('black', 32, 32, 0xff000000)],
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
        expect(await pixel(1, 32, 32), [0, 0, 0]);
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
