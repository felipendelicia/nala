import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' show PdfPageFormat, PdfColor;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import '../document/notebook.dart';
import '../document/notebook_codec.dart';
import '../editor/stroke_geometry.dart';
import 'pdf_service.dart';

class PdfExportService {
  PdfExportService(this.pdf, {this.codecEvents});
  final SendPort? codecEvents;
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
      notebook: notebook,
      backgrounds: backgrounds,
      font: (await rootBundle.load(
        'assets/fonts/NalaSans.ttf',
      )).buffer.asUint8List(),
      events: codecEvents,
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
  ({
    Notebook notebook,
    Map<String, Uint8List> backgrounds,
    Uint8List font,
    SendPort? events,
  })
  request,
) async {
  NotebookCodec.diagnostics = request.events;
  NotebookCodec.reportWork('pdf-compose');
  final notebook = request.notebook;
  final font = pw.Font.ttf(ByteData.sublistView(request.font));
  final output = pw.Document(
    title: notebook.title,
    creator: 'Nala',
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
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
            for (var i = 0; i < page.comments.length; i++)
              pw.Positioned(
                left: (page.comments[i].x - 9)
                    .clamp(0, page.width - 18)
                    .toDouble(),
                top: (page.comments[i].y - 9)
                    .clamp(0, page.height - 18)
                    .toDouble(),
                child: pw.Container(
                  width: 18,
                  height: 18,
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xff24584b),
                    shape: pw.BoxShape.circle,
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    '${i + 1}',
                    style: const pw.TextStyle(
                      color: PdfColor.fromInt(0xffffffff),
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  if (notebook.pages.any((p) => p.comments.isNotEmpty)) {
    output.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        maxPages: 200,
        build: (_) => [
          pw.Text(
            'Comentarios',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 18),
          for (var p = 0; p < notebook.pages.length; p++)
            for (var c = 0; c < notebook.pages[p].comments.length; c++) ...[
              pw.Text(
                'Hoja ${p + 1} · comentario ${c + 1}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 5),
              if (notebook.pages[p].comments[c].text.isNotEmpty)
                pw.Text(notebook.pages[p].comments[c].text),
              if (notebook.pages[p].comments[c].audioAssetId != null)
                pw.Text(
                  'Nota de voz (${_duration(notebook.pages[p].comments[c].audioDurationMs ?? 0)}). Audio disponible en Nala.',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              pw.SizedBox(height: 16),
            ],
        ],
      ),
    );
  }
  return output.save();
}

String _duration(int ms) =>
    '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';
