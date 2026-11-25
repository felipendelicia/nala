import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/page_object.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/library/library_controller.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/memory_repository.dart';

class _PhotoAssets extends MemoryAssets {
  final reads = <String>[];

  @override
  Future<Uint8List> read(String id) {
    reads.add(id);
    return super.read(id);
  }
}

Uint8List _photo(int width, int height) =>
    img.encodePng(img.Image(width: width, height: height));

Future<void> _mountLibrary(
  WidgetTester tester,
  _PhotoAssets assets,
  Notebook notebook,
) async {
  await tester.binding.setSurfaceSize(const Size(820, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = MemoryRepository();
  final library = LibraryController(repository: repository, deviceId: 'tab');
  final services = AppServices(
    root: '/unused',
    deviceId: 'tab',
    repository: repository,
    assets: assets,
    library: library,
  );
  addTearDown(services.close);
  await library.add(notebook);
  await tester.pumpWidget(MaterialApp(home: LibraryScreen(services: services)));
  await tester.pumpAndSettle();
}

Notebook _notebook() => Notebook.blank(
  id: 'fotos',
  title: 'Fotos de prueba',
  pageId: 'page',
  pattern: PaperPattern.blank,
  now: DateTime.utc(2026),
);

Finder _storedPhoto(Finder ancestor, Uint8List bytes) => find.descendant(
  of: ancestor,
  matching: find.byWidgetPredicate((widget) {
    if (widget is! Image) return false;
    final provider = widget.image;
    final original = provider is ResizeImage
        ? provider.imageProvider
        : provider;
    return original is MemoryImage && identical(original.bytes, bytes);
  }),
);

Future<Size> _decodedSize(WidgetTester tester, ImageProvider provider) async {
  final size = await tester.runAsync(() async {
    final stream = provider.resolve(const ImageConfiguration());
    final decoded = Completer<Size>();
    final listener = ImageStreamListener((info, _) {
      decoded.complete(
        Size(info.image.width.toDouble(), info.image.height.toDouble()),
      );
      info.dispose();
    }, onError: decoded.completeError);
    stream.addListener(listener);
    try {
      return await decoded.future.timeout(const Duration(seconds: 5));
    } finally {
      stream.removeListener(listener);
    }
  });
  return size!;
}

void main() {
  testWidgets(
    'la biblioteca limita el fondo y el recorte al tamaño físico de la miniatura',
    (tester) async {
      final assets = _PhotoAssets();
      final background = _photo(720, 960);
      final crop = _photo(540, 320);
      final backgroundId = await assets.put(background);
      final cropId = await assets.put(crop);
      final originalId = await assets.put(_photo(840, 600));
      final notebook = _notebook();
      await _mountLibrary(
        tester,
        assets,
        notebook.copyWith(
          pages: [
            notebook.pages.single.copyWith(
              background: PageBackground.image(backgroundId),
              objects: [
                PageObject(
                  id: 'crop',
                  kind: PageObjectKind.image,
                  x: 20,
                  y: 25,
                  width: 200,
                  height: 110,
                  assetId: cropId,
                  originalAssetId: originalId,
                ),
              ],
            ),
          ],
        ),
      );

      final photos = [
        _storedPhoto(find.byType(GridView), background),
        _storedPhoto(find.byType(GridView), crop),
      ];
      for (final photo in photos) {
        expect(photo, findsOneWidget);
        final provider = tester.widget<Image>(photo).image;
        expect(provider, isA<ResizeImage>());
        final resized = provider as ResizeImage;
        final bounds =
            tester.getRect(photo).size * tester.view.devicePixelRatio;
        expect(resized.width, closeTo(bounds.width, 2));
        expect(resized.height, closeTo(bounds.height, 2));
        expect(resized.allowUpscaling, isFalse);
      }
      expect(assets.reads, unorderedEquals([backgroundId, cropId]));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'el editor conserva la resolución original del fondo y la foto insertada',
    (tester) async {
      final assets = _PhotoAssets();
      final background = _photo(720, 960), picture = _photo(640, 480);
      final notebook = _notebook();
      await _mountLibrary(
        tester,
        assets,
        notebook.copyWith(
          pages: [
            notebook.pages.single.copyWith(
              background: PageBackground.image(await assets.put(background)),
              objects: [
                PageObject(
                  id: 'foto',
                  kind: PageObjectKind.image,
                  x: 20,
                  y: 25,
                  width: 100,
                  height: 90,
                  assetId: await assets.put(picture),
                ),
              ],
            ),
          ],
        ),
      );

      await tester.tap(find.text(notebook.title));
      await tester.pumpAndSettle();
      final editor = find.byType(EditorScreen);
      for (final bytes in [background, picture]) {
        final photo = _storedPhoto(editor, bytes);
        expect(photo, findsOneWidget);
        expect(tester.widget<Image>(photo).image, isA<MemoryImage>());
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'una portada apaisada decodifica lo necesario para cubrir la tarjeta real',
    (tester) async {
      final assets = _PhotoAssets();
      const original = Size(1200, 800);
      final coverId = await assets.put(
        _photo(original.width.toInt(), original.height.toInt()),
      );
      await _mountLibrary(
        tester,
        assets,
        _notebook().copyWith(coverAssetId: coverId),
      );

      final cover = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Image),
      );
      expect(cover, findsOneWidget);
      final image = tester.widget<Image>(cover);
      expect(image.fit, BoxFit.cover);
      final bounds = tester.getRect(cover).size * tester.view.devicePixelRatio;
      final scale = math.max(
        bounds.width / original.width,
        bounds.height / original.height,
      );
      expect(scale, lessThan(1));
      final decoded = await _decodedSize(tester, image.image);
      expect(decoded.width, closeTo(original.width * scale, 3));
      expect(decoded.height, closeTo(original.height * scale, 3));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
