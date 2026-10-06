import 'dart:io';
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
  Future<Uint8List> export(Notebook notebook) async {
    await pdf.initialize();
    final assets = <String, Uint8List>{};
    for (final page in notebook.pages) {
      final id = page.background.assetId;
      if (id != null && !assets.containsKey(id)) {
        assets[id] = await pdf.assets.read(id);
      }
    }
    return compute(
      _exportWorker,
      _ExportRequest(
        NotebookCodec.encode(notebook),
        assets,
        pdf.sessionPasswords,
        Pdfrx.pdfiumModulePath,
      ),
    );
  }
}

class _ExportRequest {
  _ExportRequest(this.notebook, this.assets, this.passwords, this.modulePath);
  final String notebook;
  final Map<String, Uint8List> assets;
  final Map<String, String> passwords;
  final String? modulePath;
}

Future<Uint8List> _exportWorker(_ExportRequest request) async {
  Pdfrx.pdfiumModulePath = request.modulePath;
  await pdfrxInitialize(tmpPath: Directory.systemTemp.path);
  final notebook = NotebookCodec.decode(request.notebook);
  final output = pw.Document(title: notebook.title, creator: 'Nala');
  PdfDocument? original;
  String? openAssetId;
  try {
    for (final page in notebook.pages) {
      Uint8List? background;
      final assetId = page.background.assetId;
      if (assetId != null) {
        if (openAssetId != assetId) {
          await original?.dispose();
          original = null;
          original = await PdfDocument.openData(
            request.assets[assetId]!,
            passwordProvider: createSimplePasswordProvider(
              request.passwords[assetId],
            ),
          );
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
          final image = img.Image.fromBytes(
            width: raster.width,
            height: raster.height,
            bytes: raster.pixels.buffer,
            bytesOffset: raster.pixels.offsetInBytes,
            numChannels: 4,
            order: img.ChannelOrder.bgra,
          );
          // Embed compressed pixels, so the PDF writer does not retain raw
          // 200-dpi RGB buffers for every page. Ink remains vector geometry.
          background = img.encodeJpg(image, quality: 95);
        } finally {
          raster.dispose();
        }
      }
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
    return await output.save();
  } finally {
    await original?.dispose();
  }
}
