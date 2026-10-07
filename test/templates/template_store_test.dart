import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:apuntes/pdf/pdf_service.dart';
import 'package:apuntes/templates/template_store.dart';
import '../support/memory_repository.dart';
import '../support/pdf_engine.dart';
import '../support/pdf_fixtures.dart';

void main() {
  test(
    'custom image paper persists dimensions and resource across reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nala-templates-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final assets = MemoryAssets();
      final pdf = PdfService(assets: assets, initialize: () async {});
      addTearDown(pdf.dispose);
      final store = TemplateStore(
        root: directory.path,
        assets: assets,
        pdf: pdf,
      );
      final own = await store.importImage(
        image.encodePng(image.Image(width: 300, height: 400)),
        name: 'Mi hoja',
      );
      final reopened = TemplateStore(
        root: directory.path,
        assets: assets,
        pdf: pdf,
      );
      final templates = await reopened.load();
      final saved = templates.singleWhere((t) => t.id == own.id);
      expect(saved.name, 'Mi hoja');
      expect(saved.width, 300);
      expect(saved.height, 400);
      expect(await assets.contains(saved.background.assetId!), isTrue);
      expect(
        templates.map((t) => t.id),
        containsAll(['blank', 'ruled', 'grid', 'dots', 'cornell', 'weekly']),
      );
      await reopened.remove(own.id);
      expect((await store.load()).where((t) => t.id == own.id), isEmpty);
    },
  );
  test(
    'PDF template preserves every original page and raster cover after reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nala-pdf-template-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final assets = MemoryAssets();
      final pdf = PdfService(
        assets: assets,
        initialize: () => initializePdfForTest(directory.path),
      );
      addTearDown(pdf.dispose);
      final store = TemplateStore(
        root: directory.path,
        assets: assets,
        pdf: pdf,
      );
      final first = await store.importPdf(await makeFixturePdf(), name: 'Guía');
      final reopened = await TemplateStore(
        root: directory.path,
        assets: assets,
        pdf: pdf,
      ).load();
      final own = reopened.where((template) => !template.builtIn).toList();
      expect(own.length, 2);
      expect(own.first.id, first.id);
      expect(own.map((template) => template.background.pageNumber), [1, 2]);
      expect(own.first.width, closeTo(595.28, .05));
      expect(own.last.width, closeTo(841.89, .05));
      for (final template in own) {
        expect(await assets.contains(template.background.assetId!), isTrue);
        final cover = image.decodePng(
          await assets.read(template.coverAssetId!),
        );
        expect(cover, isNotNull);
        expect(cover!.width, greaterThan(0));
      }
    },
  );
  test('invalid image does not enter the registry', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nala-bad-template-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final assets = MemoryAssets();
    final pdf = PdfService(assets: assets, initialize: () async {});
    addTearDown(pdf.dispose);
    final store = TemplateStore(root: directory.path, assets: assets, pdf: pdf);
    await expectLater(
      store.importImage(
        image.encodeJpg(image.Image(width: 2, height: 2)).sublist(0, 4),
        name: 'Rota',
      ),
      throwsFormatException,
    );
    expect((await store.load()).length, 6);
  });
}
