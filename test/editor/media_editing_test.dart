import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/page_object.dart';
import 'package:apuntes/media/image_editor.dart';
import 'package:apuntes/media/latex_editor.dart';

class MemoryAssets implements AssetStore {
  final values = <String, Uint8List>{};
  int next = 0;
  @override
  Future<String> put(Uint8List bytes) async {
    final id = '${next++}'.padLeft(64, '0');
    values[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List> read(String id) async => values[id]!;
  @override
  Future<bool> contains(String id) async => values.containsKey(id);
}

void main() {
  test(
    'crop produces separate bytes and reset restores original at same scale',
    () async {
      final assets = MemoryAssets();
      final source = img.Image(width: 100, height: 80);
      img.fill(source, color: img.ColorRgb8(0, 0, 255));
      final original = await assets.put(img.encodePng(source));
      final object = PageObject(
        id: 'image',
        kind: PageObjectKind.image,
        x: 10,
        y: 20,
        width: 200,
        height: 160,
        assetId: original,
      );
      final edited = await editPageImage(
        assets,
        object,
        crop: const Rect.fromLTWH(.1, .25, .5, .5),
        opacity: .4,
      );
      expect(edited.assetId, isNot(original));
      expect(edited.originalAssetId, original);
      expect(edited.width, 100);
      expect(edited.height, 80);
      expect(edited.opacity, .4);
      final pixels = img.decodePng(await assets.read(edited.assetId!))!;
      expect((pixels.width, pixels.height), (50, 40));
      expect(img.decodePng(await assets.read(original))!.width, 100);
      final croppedAgain = await editPageImage(
        assets,
        edited,
        crop: const Rect.fromLTWH(0, 0, .5, .5),
      );
      expect(croppedAgain.originalAssetId, original);
      expect(croppedAgain.assetId, isNot(edited.assetId));
      expect(img.decodePng(await assets.read(edited.assetId!))!.width, 50);
      final reset = await editPageImage(assets, croppedAgain, reset: true);
      expect(reset.assetId, original);
      expect(reset.originalAssetId, isNull);
      expect((reset.width, reset.height), (200, 160));
      final recrop = await editPageImage(
        assets,
        reset,
        crop: const Rect.fromLTWH(0, 0, .25, .25),
      );
      expect(
        (
          img.decodePng(await assets.read(recrop.assetId!))!.width,
          recrop.originalAssetId,
        ),
        (25, original),
      );
    },
  );
  test('crop rejects nonfinite, empty and out of image bounds', () async {
    final assets = MemoryAssets();
    final id = await assets.put(
      img.encodePng(img.Image(width: 20, height: 20)),
    );
    final object = PageObject(
      id: 'i',
      kind: PageObjectKind.image,
      x: 0,
      y: 0,
      width: 20,
      height: 20,
      assetId: id,
    );
    for (final rect in [
      Rect.zero,
      const Rect.fromLTWH(-.1, 0, .5, 1),
      const Rect.fromLTWH(0, 0, 2, 1),
      Rect.fromLTWH(double.nan, 0, 1, 1),
    ]) {
      await expectLater(
        editPageImage(assets, object, crop: rect),
        throwsFormatException,
      );
    }
  });
  testWidgets('invalid math cannot be saved and existing source is editable', (
    tester,
  ) async {
    final assets = MemoryAssets();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLatexEditor(context, assets: assets),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, r'\frac{');
    await tester.pumpAndSettle();
    expect(find.textContaining('Fórmula inválida'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Insertar'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).first, r'\frac{1}{2}');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Insertar'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'math capture retains source, transparent pixels and edit identity',
    (tester) async {
      final assets = MemoryAssets();
      PageObject? saved;
      Future<void> open(BuildContext context, [PageObject? object]) async {
        saved = await showLatexEditor(
          context,
          assets: assets,
          object: object,
          id: 'equation',
          position: const Offset(30, 50),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => open(context),
                  child: const Text('Create'),
                ),
                TextButton(
                  onPressed: () => open(context, saved),
                  child: const Text('Edit'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, r'\frac{1}{2}');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Insertar'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.text, r'\frac{1}{2}');
      expect(saved!.id, 'equation');
      expect((saved!.x, saved!.y), (30, 50));
      final oldAsset = saved!.assetId;
      final pixels = img.decodePng(assets.values[oldAsset]!)!;
      expect(pixels.getPixel(0, 0).a, 0);
      expect(pixels.any((pixel) => pixel.a > 0), true);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        r'\frac{1}{2}',
      );
      await tester.enterText(find.byType(TextField).first, 'x^2');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(saved!.text, 'x^2');
      expect(saved!.id, 'equation');
      expect(saved!.assetId, isNot(oldAsset));
    },
  );
}
