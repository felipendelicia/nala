import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import '../document/notebook.dart';
import '../document/notebook_codec.dart';
import '../editor/stroke_geometry.dart';
import 'pdf_service.dart';

class PdfExportService {
  PdfExportService(this.pdf);
  final PdfService pdf;
  Future<Uint8List?> exportWithUnlock(
    Notebook snapshot,
    Future<bool> Function(String assetId) unlock,
  ) async {
    while (true) {
      try {
        return await export(snapshot);
      } on PdfExportPasswordRequired catch (e) {
        if (!await unlock(e.assetId)) return null;
      }
    }
  }

  Future<Uint8List> export(Notebook notebook) async {
    await pdf.initialize();
    // PDFium has process-wide native callbacks. All native work must use the
    // engine's existing worker; only pixel compression and PDF writing get a
    // separate compute isolate. Reinitializing PDFium there invalidates the
    // editor's font callbacks and can terminate the application.
    final backgrounds = <String, Uint8List>{};
    PdfDocument? original;
    String? openAssetId;
    try {
      for (final page in notebook.pages) {
        final assetId = page.background.assetId;
        if (assetId != null) {
          if (openAssetId != assetId) {
            await original?.dispose();
            original = null;
            try {
              original = await PdfDocument.openData(
                await pdf.assets.read(assetId),
                passwordProvider: createSimplePasswordProvider(
                  pdf.sessionPasswords[assetId],
                ),
              );
            } on PdfPasswordException {
              throw PdfExportPasswordRequired(assetId);
            }
            openAssetId = assetId;
          }
          final source = original!.pages[page.background.pageNumber! - 1];
          final width = (source.width * 200 / 72).ceil(),
              height = (source.height * 200 / 72).ceil();
          if (width * height > 32 * 1024 * 1024) {
            throw const FormatException(
              'Esta página es demasiado grande para exportarla a 200 dpi.',
            );
          }
          final raster = await source.render(
            width: width,
            height: height,
            fullWidth: width.toDouble(),
            fullHeight: height.toDouble(),
            backgroundColor: 0xffffffff,
          );
          if (raster == null) {
            throw StateError('No se pudo preparar el fondo PDF');
          }
          try {
            backgrounds[page.id] = await compute(_encodeJpeg, (
              pixels: Uint8List.fromList(raster.pixels),
              width: raster.width,
              height: raster.height,
            ));
          } finally {
            raster.dispose();
          }
        }
      }
    } finally {
      await original?.dispose();
    }
    return compute(_composePdf, (
      notebook: NotebookCodec.encode(notebook),
      backgrounds: backgrounds,
    ));
  }
}

class PdfExportPasswordRequired implements Exception {
  const PdfExportPasswordRequired(this.assetId);
  final String assetId;
}

Uint8List _encodeJpeg(PdfPixels raster) => img.encodeJpg(
  img.Image.fromBytes(
    width: raster.width,
    height: raster.height,
    bytes: raster.pixels.buffer,
    bytesOffset: raster.pixels.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.bgra,
  ),
  quality: 95,
);

Future<Uint8List> _composePdf(
  ({String notebook, Map<String, Uint8List> backgrounds}) request,
) async {
  final notebook = NotebookCodec.decode(request.notebook);
  final output = pw.Document(title: notebook.title, creator: 'Nala');
  for (final page in notebook.pages) {
    final background = request.backgrounds[page.id];
    final svg = StrokeGeometry.svg(page);
    final image = background == null ? null : pw.MemoryImage(background);
    output.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(page.width, page.height, marginAll: 0),
        build: (_) => pw.Stack(
          children: [
            if (image != null)
              pw.Positioned.fill(child: pw.Image(image, fit: pw.BoxFit.fill)),
            pw.Positioned.fill(
              child: pw.SvgImage(svg: svg, fit: pw.BoxFit.fill),
            ),
          ],
        ),
      ),
    );
  }
  return output.save();
}
