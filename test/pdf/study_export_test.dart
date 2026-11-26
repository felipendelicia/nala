import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/pdf/pdf_export_service.dart';
import 'package:apuntes/pdf/pdf_service.dart';
import '../support/pdf_engine.dart';
import '../support/study_fixture.dart';

void main() {
  test('PDF rasterizes the image and Unicode text below ink', () async {
    final dir = await Directory.systemTemp.createTemp('nala-study-export-');
    final assets = FileAssetStore('${dir.path}/assets');
    final service = PdfService(
      assets: assets,
      initialize: () => initializePdfForTest(dir.path),
    );
    addTearDown(() async {
      service.dispose();
      await dir.delete(recursive: true);
    });
    final blue = img.Image(width: 8, height: 8);
    img.fill(blue, color: img.ColorRgb8(0, 0, 255));
    final imageId = await assets.put(img.encodePng(blue));
    final map = studyPayload();
    map['pages'][0]['background'] = {'kind': 'paper', 'pattern': 'blank'};
    map['pages'][0]['objects'][1]['assetId'] = imageId;
    map['pages'][0]['objects'][1]['rotation'] = 0;
    map['pages'][0]['strokes'][0]['points'] = [
      {'x': 70, 'y': 160, 'pressure': 1},
    ];
    map['pages'][0]['strokes'][0]['width'] = 8;
    map['pages'][0]['strokes'][0]['argb'] = 0xffff0000;
    final bytes = await PdfExportService(
      service,
    ).export(NotebookCodec.decode(jsonEncode(map)));
    final document = await PdfDocument.openData(bytes);
    try {
      expect((await document.pages.first.loadText())?.fullText ?? '', isEmpty);
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

        final darkColumns = <int>{};
        var textPixels = 0;
        for (var y = 70; y < 120; y++) {
          for (var x = 50; x < 250; x++) {
            if (pixel(x, y).every((channel) => channel < 150)) {
              textPixels++;
              darkColumns.add(x);
            }
          }
        }
        expect(textPixels, greaterThan(30));
        expect(darkColumns.length, greaterThan(28));
        expect(pixel(60, 150), [closeTo(0, 5), closeTo(0, 5), closeTo(255, 5)]);
        expect(pixel(70, 160), [closeTo(255, 5), closeTo(0, 5), closeTo(0, 5)]);
      } finally {
        raster.dispose();
      }
      await Directory('.dart_tool/pdf-qa').create(recursive: true);
      await File('.dart_tool/pdf-qa/study-objects.pdf').writeAsBytes(bytes);
    } finally {
      await document.dispose();
    }
  });

  test('image backgrounds export without opening them as PDFs', () async {
    final dir = await Directory.systemTemp.createTemp('nala-image-background-');
    final assets = FileAssetStore('${dir.path}/assets');
    final service = PdfService(
      assets: assets,
      initialize: () => initializePdfForTest(dir.path),
    );
    addTearDown(() async {
      service.dispose();
      await dir.delete(recursive: true);
    });
    final green = img.Image(width: 8, height: 8);
    img.fill(green, color: img.ColorRgb8(0, 255, 0));
    final id = await assets.put(img.encodePng(green));
    final map = studyPayload();
    map['pages'][0]['objects'] = [];
    map['pages'][0]['strokes'] = [];
    map['pages'][0]['background'] = {'kind': 'image', 'assetId': id};
    final result = await PdfExportService(
      service,
    ).export(NotebookCodec.decode(jsonEncode(map)));
    final document = await PdfDocument.openData(result);
    try {
      final raster = (await document.pages.first.render())!;
      try {
        final at = (100 * raster.width + 100) * 4;
        expect(
          [raster.pixels[at + 2], raster.pixels[at + 1], raster.pixels[at]],
          [closeTo(0, 5), closeTo(255, 5), closeTo(0, 5)],
        );
      } finally {
        raster.dispose();
      }
    } finally {
      await document.dispose();
    }
  });
}
