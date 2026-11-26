import 'dart:isolate';
import 'dart:ui' show Size;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart'
    show PdfColor, PdfGraphicState, PdfPage, PdfPageFormat, PdfStream;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx_engine/pdfrx_engine.dart'
    show PdfDocument, PdfPasswordException, createSimplePasswordProvider;
import '../document/deferred_notebook_page.dart';
import '../document/markdown_content.dart';
import '../document/notebook.dart';
import '../document/notebook_codec.dart';
import '../document/page_object.dart';
import '../editor/markdown_sheet.dart';
import '../editor/paper_background.dart';
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
    final images = <String, Uint8List>{};
    PdfDocument? original;
    String? openAssetId;
    try {
      for (final page in notebook.pages) {
        final assetId = page.background.assetId;
        if (page.background.isImage) {
          backgrounds[page.id] = await pdf.assets.read(assetId!);
        } else if (page.background.isPdf) {
          if (openAssetId != assetId) {
            await original?.dispose();
            original = null;
            try {
              original = await PdfDocument.openData(
                await pdf.assets.read(assetId!),
                passwordProvider: createSimplePasswordProvider(
                  pdf.sessionPasswords[assetId],
                ),
              );
            } on PdfPasswordException {
              throw PdfExportPasswordRequired(assetId!);
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
        if (page is DeferredNotebookPage && !page.isReady) {
          await page.prepare();
        }
        for (final object in page.objects) {
          if (object.kind != PageObjectKind.text &&
              !images.containsKey(object.assetId)) {
            images[object.assetId!] = await pdf.assets.read(object.assetId!);
          }
        }
      }
    } finally {
      await original?.dispose();
    }
    return compute(_composePdf, (
      notebook: notebook,
      backgrounds: backgrounds,
      images: images,
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
    Map<String, Uint8List> images,
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
    final markdown = page.markdown;
    final image = background == null ? null : pw.MemoryImage(background);
    output.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(page.width, page.height, marginAll: 0),
        build: (_) => pw.Stack(
          children: [
            if (page.background.pattern != null)
              pw.Positioned.fill(
                child: pw.SvgImage(
                  svg: paperBackgroundSvg(
                    page.background.pattern!,
                    Size(page.width, page.height),
                  ),
                  fit: pw.BoxFit.fill,
                ),
              ),
            if (image != null)
              pw.Positioned.fill(child: pw.Image(image, fit: pw.BoxFit.fill)),
            if (markdown != null)
              pw.Positioned.fill(child: _markdownPage(markdown, page.width)),
            for (final object in page.objects)
              pw.Positioned(
                left: object.x,
                top: object.y,
                child: pw.Transform.rotate(
                  // PDF coordinates point upward; canvas coordinates downward.
                  angle: -object.rotation,
                  child: pw.SizedBox(
                    width: object.width,
                    height: object.height,
                    child: pw.Opacity(
                      opacity: object.opacity,
                      child: pw.ClipRect(
                        child: object.kind != PageObjectKind.text
                            ? pw.Image(
                                pw.MemoryImage(request.images[object.assetId]!),
                                fit: pw.BoxFit.fill,
                              )
                            : pw.Align(
                                alignment: pw.Alignment.topLeft,
                                child: pw.Text(
                                  object.text,
                                  style: pw.TextStyle(
                                    fontSize: object.fontSize,
                                    decoration: object.link == null
                                        ? null
                                        : pw.TextDecoration.underline,
                                    color: PdfColor.fromInt(object.argb),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            if (page.strokes.isNotEmpty || page.comments.isNotEmpty)
              pw.Positioned.fill(
                child: _PageAnnotations(
                  page,
                  child: page.comments.isEmpty ? null : _commentMarkers(page),
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
  // Composition already runs in a worker isolate. Writing here avoids
  // transferring the populated document and its page streams to another one.
  final bytes = PdfStream();
  await output.write(bytes);
  return bytes.output();
}

pw.Widget _markdownPage(String markdown, double width) => pw.Padding(
  padding: const pw.EdgeInsets.all(markdownSheetMargin),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      for (final block in parseMarkdown(markdown))
        pw.Padding(
          padding: pw.EdgeInsets.only(
            left: block.indent.clamp(0, (width - 2 * markdownSheetMargin) / 4),
            bottom: block.gap,
          ),
          child: block.divider
              ? pw.Container(height: 1, color: const PdfColor(.8, .8, .8))
              : pw.RichText(
                  text: pw.TextSpan(
                    style: pw.TextStyle(
                      color: const PdfColor(.125, .125, .125),
                      fontSize: block.sizeFor(markdownSheetFontSize),
                      fontWeight: block.heading > 0 ? pw.FontWeight.bold : null,
                      lineSpacing: markdownSheetFontSize * .12,
                    ),
                    children: [
                      for (final run in block.runs)
                        pw.TextSpan(
                          text: run.text,
                          style: _markdownRunStyle(run),
                        ),
                    ],
                  ),
                ),
        ),
    ],
  ),
);

pw.TextStyle _markdownRunStyle(MarkdownRun run) => pw.TextStyle(
  fontWeight: run.emphasis.contains(MarkdownEmphasis.bold)
      ? pw.FontWeight.bold
      : null,
  fontStyle: run.emphasis.contains(MarkdownEmphasis.italic)
      ? pw.FontStyle.italic
      : null,
  decoration: pw.TextDecoration.combine([
    if (run.emphasis.contains(MarkdownEmphasis.strike))
      pw.TextDecoration.lineThrough,
    if (run.link != null) pw.TextDecoration.underline,
  ]),
);

pw.Widget _commentMarkers(NotebookPage page) => pw.Stack(
  children: [
    for (var i = 0; i < page.comments.length; i++)
      pw.Positioned(
        left: (page.comments[i].x - 9).clamp(0, page.width - 18).toDouble(),
        top: (page.comments[i].y - 9).clamp(0, page.height - 18).toDouble(),
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
);

/// Appends ink and comments above the full, zero-margin page background.
class _PageAnnotations extends pw.SingleChildWidget {
  _PageAnnotations(this.page, {super.child});

  final NotebookPage page;

  @override
  void paint(pw.Context context) {
    super.paint(context);
    if (page.strokes.isEmpty) {
      child?.paint(context);
      return;
    }
    _paintInk(context.page, page.height, page.strokes);
    if (child != null) {
      final canvas = context.page.getGraphics()
        ..setGraphicState(const PdfGraphicState(opacity: 1));
      child!.paint(context.copyWith(canvas: canvas));
    }
  }
}

void _paintInk(PdfPage page, double height, List<InkStroke> strokes) {
  var canvas = page.getGraphics();
  var contours = 0;

  void beginContour() {
    // The PDF library grows streams by a fixed increment, copying the entire
    // contents. Keep each stream small. A PDF page reads its contents streams
    // in sequence, so a stroke can still be filled once across boundaries.
    const contoursPerStream = 1024;
    if (contours == contoursPerStream) {
      canvas = page.getGraphics();
      contours = 0;
    }
    contours++;
  }

  for (final stroke in strokes) {
    final color = PdfColor.fromInt(stroke.argb);
    final opacity = stroke.tool == InkTool.highlighter ? 1 / 3 : color.alpha;
    final outline = StrokeGeometry.outline(stroke);
    canvas
      ..setFillColor(color)
      ..setGraphicState(PdfGraphicState(opacity: opacity));
    for (final circle in outline.circles) {
      beginContour();
      final center = circle.center;
      final radius = circle.width / 2;
      // Match the polygon winding after flipping from page to PDF coordinates.
      canvas.drawEllipse(
        center.dx,
        height - center.dy,
        radius,
        radius,
        clockwise: false,
      );
    }
    for (final corners in outline.polygons) {
      beginContour();
      canvas.moveTo(corners.first.dx, height - corners.first.dy);
      for (final corner in corners.skip(1)) {
        canvas.lineTo(corner.dx, height - corner.dy);
      }
      canvas.closePath();
    }
    // One fill applies the stroke opacity once even where its contours overlap.
    canvas.fillPath();
  }
}

String _duration(int ms) =>
    '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}';
