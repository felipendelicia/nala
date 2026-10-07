import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/page_object.dart';
import 'package:apuntes/pdf/pdf_export_service.dart';
import 'package:apuntes/pdf/pdf_service.dart';
import '../support/pdf_engine.dart';
import '../support/fixtures.dart';

void main() {
  test(
    'PDF applies opacity and paints math PNG instead of its source',
    () async {
      final dir = await Directory.systemTemp.createTemp('nala-media-export-');
      final assets = FileAssetStore('${dir.path}/assets');
      final service = PdfService(
        assets: assets,
        initialize: () => initializePdfForTest(dir.path),
      );
      addTearDown(() async {
        service.dispose();
        await dir.delete(recursive: true);
      });
      final blue = img.Image(width: 10, height: 10);
      img.fill(blue, color: img.ColorRgb8(0, 0, 255));
      final id = await assets.put(img.encodePng(blue));
      final image = PageObject.fromJson({
        'id': 'image',
        'kind': 'image',
        'x': 50,
        'y': 50,
        'width': 40,
        'height': 40,
        'assetId': id,
        'opacity': .5,
      });
      final formula = PageObject.fromJson({
        'id': 'math',
        'kind': 'latex',
        'text': r'\frac{a}{b}',
        'x': 120,
        'y': 50,
        'width': 40,
        'height': 40,
        'assetId': id,
      });
      final base = fixtureNotebook();
      final book = base.copyWith(
        pages: [
          base.pages.single.copyWith(
            background: const PageBackground.paper(PaperPattern.blank),
            strokes: [],
            objects: [image, formula],
          ),
        ],
      );
      final result = await PdfExportService(service).export(book);
      final document = await PdfDocument.openData(result);
      try {
        final raster = (await document.pages.first.render(
          backgroundColor: 0xffffffff,
        ))!;
        try {
          List<int> pixel(int x, int y) {
            final at = (y * raster.width + x) * 4;
            return [
              raster.pixels[at + 2],
              raster.pixels[at + 1],
              raster.pixels[at],
            ];
          }

          final faded = pixel(60, 60);
          expect(faded[0], closeTo(128, 2));
          expect(faded[1], closeTo(128, 2));
          expect(faded[2], 255);
          expect(pixel(130, 60), [0, 0, 255]);
          expect(
            (await document.pages.first.loadText())!.fullText,
            isNot(contains(r'\frac')),
          );
        } finally {
          raster.dispose();
        }
      } finally {
        await document.dispose();
      }
    },
  );
}
