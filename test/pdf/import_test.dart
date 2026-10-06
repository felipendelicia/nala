import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:image/image.dart' as img;
import 'package:apuntes/pdf/pdf_service.dart';
import '../support/pdf_fixtures.dart';
import '../support/pdf_engine.dart';

void main() {
  late Directory dir;
  late FileAssetStore assets;
  late PdfService service;
  var id = 0;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nala-pdf-');
    assets = FileAssetStore('${dir.path}/assets');
    service = PdfService(
      assets: assets,
      initialize: () => initializePdfForTest(dir.path),
    );
    id = 0;
  });
  tearDown(() async {
    service.dispose();
    await dir.delete(recursive: true);
  });
  Future<Notebook> import(Uint8List bytes, {String? password}) =>
      service.importDocument(
        bytes: bytes,
        title: 'Guía',
        documentId: 'guide-1',
        newId: () => 'id-${++id}',
        now: DateTime.utc(2026, 10, 6),
        password: password,
      );

  test(
    'PDF importado conserva tamaños y referencias y guarda el original',
    () async {
      final bytes = await makeFixturePdf();
      final note = await import(bytes);
      expect(note.pages, hasLength(2));
      expect(note.pages[0].width, closeTo(595.28, .01));
      expect(note.pages[0].height, closeTo(841.89, .01));
      expect(note.pages[1].width, closeTo(841.89, .01));
      expect(note.pages[1].height, closeTo(595.28, .01));
      expect(note.pages[0].background.pageNumber, 1);
      expect(note.pages[1].background.pageNumber, 2);
      expect(await assets.read(note.pages[0].background.assetId!), bytes);
    },
  );
  test('un PDF inválido no escribe recursos ni crea un documento', () async {
    await expectLater(
      import(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<PdfException>()),
    );
    expect(await dir.list(recursive: true).where((e) => e is File).length, 0);
  });
  test('un PDF rotado conserva su orientación visual', () async {
    final note = await import(
      await File('test/support/pdf/rotated.pdf').readAsBytes(),
    );
    expect(note.pages.single.width, closeTo(841.89, .01));
    expect(note.pages.single.height, closeTo(595.28, .01));
    final png = await service.renderBackground(
      note.pages.single.background.assetId!,
      1,
      scale: .5,
    );
    final image = img.decodePng(png)!;
    expect((image.width, image.height), (421, 298));
    final corner = image.getPixel(413, 8);
    expect(corner.r, greaterThan(240));
    expect(corner.g, lessThan(30));
  });
  test(
    'un PDF protegido pide clave y la clave no queda en el documento',
    () async {
      final bytes = await File('test/support/pdf/protected.pdf').readAsBytes();
      await expectLater(import(bytes), throwsA(isA<PdfPasswordException>()));
      await expectLater(
        import(bytes, password: 'incorrecta'),
        throwsA(isA<PdfPasswordException>()),
      );
      final note = await import(bytes, password: 'nala-test');
      expect(NotebookCodec.encode(note), isNot(contains('nala-test')));
      final png = await service.renderBackground(
        note.pages.single.background.assetId!,
        1,
        scale: .5,
      );
      expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      service.dispose();
      service = PdfService(
        assets: assets,
        initialize: () => initializePdfForTest(dir.path),
      );
      await expectLater(
        service.renderBackground(
          note.pages.single.background.assetId!,
          1,
          scale: .5,
        ),
        throwsA(isA<PdfPasswordException>()),
      );
      await service.unlock(note.pages.single.background.assetId!, 'nala-test');
      expect(
        await service.renderBackground(
          note.pages.single.background.assetId!,
          1,
          scale: .5,
        ),
        isNotEmpty,
      );
    },
  );
  test('cancelar un fondo evita publicar una imagen obsoleta', () async {
    final note = await import(await makeFixturePdf());
    final cancellation = PdfRenderCancellation()..cancel();
    await expectLater(
      service.renderBackground(
        note.pages[0].background.assetId!,
        1,
        scale: 1,
        cancellation: cancellation,
      ),
      throwsA(isA<PdfRenderCancelled>()),
    );
    final image = img.decodePng(
      await service.renderBackground(
        note.pages[0].background.assetId!,
        1,
        scale: .5,
      ),
    )!;
    expect((image.width, image.height), (298, 421));
  });
}
