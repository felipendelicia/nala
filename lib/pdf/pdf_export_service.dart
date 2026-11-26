import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' show PdfPageFormat, PdfStream;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx_engine/pdfrx_engine.dart'
    show
        PdfDocument,
        PdfPage,
        PdfPasswordException,
        createSimplePasswordProvider;

import '../document/deferred_notebook_page.dart';
import '../document/notebook.dart';
import '../document/notebook_codec.dart';
import '../document/page_comment.dart';
import 'pdf_page_raster.dart';
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
    final pages = <_ExportSheet>[];
    final comments = <_SheetComments>[];
    PdfDocument? original;
    String? openAssetId;
    try {
      for (final (index, page) in notebook.pages.indexed) {
        if (page is DeferredNotebookPage && !page.isReady) {
          await page.prepare();
        }
        final (width, height) = _exportPixelSize(page);
        ui.Image? background;
        final ui.Image image;
        try {
          if (page.background.isPdf) {
            final assetId = page.background.assetId!;
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
            background = await _renderPdfBackground(source, width, height);
          }
          image = await rasterizeExportPage(
            page,
            pdf.assets,
            width,
            height,
            pdfBackground: background,
          );
        } finally {
          background?.dispose();
        }
        final jpeg = await _compressExportPage(image);
        pages.add((width: page.width, height: page.height, jpeg: jpeg));
        if (page.comments.isNotEmpty) {
          comments.add((pageNumber: index + 1, comments: page.comments));
        }
      }
    } finally {
      await original?.dispose();
    }
    final font = comments.isEmpty
        ? null
        : await rootBundle.load('assets/fonts/NalaSans.ttf');
    return compute(_composePdf, (
      title: notebook.title,
      pages: pages,
      comments: comments,
      font: font,
      events: codecEvents,
    ));
  }
}

class PdfExportPasswordRequired implements Exception {
  const PdfExportPasswordRequired(this.assetId);
  final String assetId;
}

(int, int) _exportPixelSize(NotebookPage page) {
  const preferredScale = 144 / 72;
  const maxPixelArea = 8 * 1024 * 1024;
  const maxDimension = 4096;
  final scale = math.min(
    preferredScale,
    math.min(
      math.sqrt(maxPixelArea / (page.width * page.height)),
      maxDimension / math.max(page.width, page.height),
    ),
  );
  return (
    math.max(1, (page.width * scale).ceil()),
    math.max(1, (page.height * scale).ceil()),
  );
}

Future<ui.Image> _renderPdfBackground(
  PdfPage source,
  int width,
  int height,
) async {
  // PDFium continues to render on its existing native worker.
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
  final ui.ImmutableBuffer pixels;
  try {
    pixels = await ui.ImmutableBuffer.fromUint8List(raster.pixels);
  } finally {
    raster.dispose();
  }
  try {
    final descriptor = ui.ImageDescriptor.raw(
      pixels,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.bgra8888,
    );
    try {
      final codec = await descriptor.instantiateCodec();
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    pixels.dispose();
  }
}

typedef _ExportSheet = ({double width, double height, Uint8List jpeg});
typedef _SheetComments = ({int pageNumber, List<PageComment> comments});

Future<Uint8List> _compressExportPage(ui.Image image) async {
  final width = image.width;
  final height = image.height;
  final ByteData pixels;
  try {
    pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
  }
  return compute(_encodePageJpeg, (
    width: width,
    height: height,
    rgba: TransferableTypedData.fromList([
      pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
    ]),
  ));
}

Uint8List _encodePageJpeg(
  ({int width, int height, TransferableTypedData rgba}) frame,
) {
  final rgba = frame.rgba.materialize().asUint8List();
  final image = img.Image(width: frame.width, height: frame.height);
  final rgb = image.getBytes();
  // The page was painted on opaque white. Pack RGB to skip alpha blending
  // and per-pixel conversion in the JPEG encoder.
  for (
    var source = 0, target = 0;
    target < rgb.length;
    source += 4, target += 3
  ) {
    rgb[target] = rgba[source];
    rgb[target + 1] = rgba[source + 1];
    rgb[target + 2] = rgba[source + 2];
  }
  return img.encodeJpg(image, quality: 93);
}

Future<Uint8List> _composePdf(
  ({
    String title,
    List<_ExportSheet> pages,
    List<_SheetComments> comments,
    ByteData? font,
    SendPort? events,
  })
  request,
) async {
  NotebookCodec.diagnostics = request.events;
  NotebookCodec.reportWork('pdf-compose');
  final font = request.font == null ? null : pw.Font.ttf(request.font!);
  final output = pw.Document(
    title: request.title,
    creator: 'Nala',
    theme: font == null ? null : pw.ThemeData.withFont(base: font, bold: font),
  );
  for (final page in request.pages) {
    final image = pw.MemoryImage(page.jpeg);
    output.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(page.width, page.height, marginAll: 0),
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ),
    );
  }
  if (request.comments.isNotEmpty) {
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
          for (final sheet in request.comments)
            for (final (index, comment) in sheet.comments.indexed) ...[
              pw.Text(
                'Hoja ${sheet.pageNumber} · comentario ${index + 1}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 5),
              if (comment.text.isNotEmpty) pw.Text(comment.text),
              if (comment.audioAssetId != null)
                pw.Text(
                  'Nota de voz (${_duration(comment.audioDurationMs ?? 0)}). Audio disponible en Nala.',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              pw.SizedBox(height: 16),
            ],
        ],
      ),
    );
  }
  // Writing here avoids transferring the populated document to another worker.
  final bytes = PdfStream();
  await output.write(bytes);
  return bytes.output();
}

String _duration(int ms) =>
    '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';
