import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import '../document/asset_store.dart';
import '../document/notebook.dart';
import '../document/page_object.dart';
import '../pdf/pdf_service.dart';

class RecognitionCancelled implements Exception {}

class RecognitionAvailability {
  const RecognitionAvailability({
    required this.available,
    required this.ready,
    required this.message,
    this.canDownload = false,
  });
  final bool available, ready, canDownload;
  final String message;
}

abstract class PageRecognition {
  Future<RecognitionAvailability> status();
  Future<void> downloadModel();
  Future<void> deleteModel();
  Future<String> recognize(NotebookPage page);
  void cancel();
  void dispose() => cancel();
}

PageRecognition nativePageRecognition({
  required AssetStore assets,
  required PdfService pdf,
}) => Platform.isAndroid
    ? AndroidInkRecognition()
    : LinuxPageOcr(assets: assets, pdf: pdf);

class AndroidInkRecognition extends PageRecognition {
  AndroidInkRecognition({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('nala/ink-recognition');
  final MethodChannel _channel;
  int _generation = 0;
  @override
  Future<RecognitionAvailability> status() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('status');
      final available = result?['available'] == true,
          ready = result?['downloaded'] == true;
      return RecognitionAvailability(
        available: available,
        ready: ready,
        canDownload: available,
        message: !available
            ? 'El reconocimiento manuscrito no está disponible.'
            : ready
            ? 'Manuscrito español listo · procesamiento local'
            : 'Descargá el modelo español para reconocer manuscritos (aprox. 20 MB).',
      );
    } on MissingPluginException {
      return const RecognitionAvailability(
        available: false,
        ready: false,
        message: 'El reconocimiento manuscrito requiere Android con ML Kit.',
      );
    }
  }

  @override
  Future<void> downloadModel() async {
    await _channel.invokeMethod<bool>('download');
  }

  @override
  Future<void> deleteModel() async {
    await _channel.invokeMethod<bool>('delete');
  }

  @override
  Future<String> recognize(NotebookPage page) async {
    final generation = ++_generation;
    final availability = await status();
    if (!availability.ready) {
      throw StateError('Primero descargá el modelo español.');
    }
    if (generation != _generation) throw RecognitionCancelled();
    if (page.strokes.isEmpty) return '';
    final result =
        await _channel.invokeMethod<String>('recognize', {
          'strokes': [
            for (final stroke in page.strokes)
              [
                for (final point in stroke.points) {'x': point.x, 'y': point.y},
              ],
          ],
        }) ??
        '';
    if (generation != _generation) throw RecognitionCancelled();
    return result;
  }

  @override
  void cancel() {
    _generation++;
    unawaited(_channel.invokeMethod<void>('cancel').catchError((Object _) {}));
  }
}

/// Optional local OCR for scans and printed text. Its availability is explicit;
/// Tesseract is never presented as equivalent to Android's digital ink model.
class LinuxPageOcr extends PageRecognition {
  LinuxPageOcr({required this.assets, required this.pdf});
  final AssetStore assets;
  final PdfService pdf;
  Process? _process;
  PdfRenderCancellation? _renderCancellation;
  int _generation = 0;
  @override
  Future<RecognitionAvailability> status() async {
    if (!Platform.isLinux) {
      return const RecognitionAvailability(
        available: false,
        ready: false,
        message: 'OCR local no disponible en esta plataforma.',
      );
    }
    try {
      final result = await Process.run('tesseract', [
        '--list-langs',
      ]).timeout(const Duration(seconds: 4));
      final languages = '${result.stdout}\n${result.stderr}'.split(
        RegExp(r'\s+'),
      );
      if (result.exitCode == 0 && languages.contains('spa')) {
        return const RecognitionAvailability(
          available: true,
          ready: true,
          message:
              'OCR local español (Tesseract) · para texto impreso y escaneos; la escritura manuscrita puede fallar.',
        );
      }
      return const RecognitionAvailability(
        available: false,
        ready: false,
        message:
            'Tesseract no tiene el idioma español (spa). Podés editar el texto reconocido manualmente.',
      );
    } catch (_) {
      return const RecognitionAvailability(
        available: false,
        ready: false,
        message:
            'OCR local no disponible: falta Tesseract con español (spa). Podés usar texto reconocido en Android o editarlo manualmente.',
      );
    }
  }

  @override
  Future<void> downloadModel() async => throw UnsupportedError(
    'Instalá Tesseract y el idioma español desde tu sistema.',
  );
  @override
  Future<void> deleteModel() async =>
      throw UnsupportedError('El modelo OCR se administra desde tu sistema.');
  @override
  Future<String> recognize(NotebookPage page) async {
    final generation = ++_generation;
    if (!(await status()).ready) throw StateError('OCR español no disponible.');
    if (generation != _generation) throw RecognitionCancelled();
    final cancellation = _renderCancellation = PdfRenderCancellation();
    final directory = await Directory.systemTemp.createTemp('nala-local-ocr-');
    try {
      final bytes = await _renderPage(page, assets, pdf, cancellation);
      if (generation != _generation) throw RecognitionCancelled();
      final input = File('${directory.path}/page.png');
      await input.writeAsBytes(bytes);
      final process = _process = await Process.start('tesseract', [
        input.path,
        '${directory.path}/recognized',
        '-l',
        'spa',
        '--psm',
        '3',
      ]);
      final outputs = Future.wait([
        process.stdout.drain<void>(),
        process.stderr.drain<void>(),
      ]);
      final exit = await process.exitCode.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          process.kill();
          throw TimeoutException('OCR tardó demasiado.');
        },
      );
      await outputs;
      if (generation != _generation) throw RecognitionCancelled();
      if (exit != 0) throw StateError('No se pudo reconocer esta página.');
      return (await File(
        '${directory.path}/recognized.txt',
      ).readAsString()).trim();
    } finally {
      _process = null;
      _renderCancellation = null;
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  @override
  void cancel() {
    _generation++;
    _process?.kill();
    _renderCancellation?.cancel();
  }
}

Future<Uint8List> _renderPage(
  NotebookPage page,
  AssetStore assets,
  PdfService pdf,
  PdfRenderCancellation cancellation,
) async {
  final scale = math.min(
    2.0,
    math.sqrt(8 * 1024 * 1024 / (page.width * page.height)),
  );
  final recorder = ui.PictureRecorder();
  // Record once; all images are disposed after their commands are rasterized.
  final drawing = Canvas(recorder)..scale(scale);
  drawing.drawRect(
    Rect.fromLTWH(0, 0, page.width, page.height),
    Paint()..color = const Color(0xffffffff),
  );
  final images = <ui.Image>[];
  Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final image = (await codec.getNextFrame()).image;
      images.add(image);
      return image;
    } finally {
      codec.dispose();
    }
  }

  try {
    if (page.background.assetId != null) {
      final bytes = page.background.pageNumber == null
          ? await assets.read(page.background.assetId!)
          : await pdf.renderBackground(
              page.background.assetId!,
              page.background.pageNumber!,
              scale: scale,
              cancellation: cancellation,
            );
      final image = await decode(bytes);
      drawing.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, page.width, page.height),
        Paint(),
      );
    }
    for (final stroke in page.strokes) {
      final paint = Paint()
        ..color = Color(stroke.argb)
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round;
      if (stroke.points.length == 1) {
        final p = stroke.points.single;
        drawing.drawCircle(Offset(p.x, p.y), stroke.width / 2, paint);
      }
      for (var i = 1; i < stroke.points.length; i++) {
        final a = stroke.points[i - 1], b = stroke.points[i];
        drawing.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
      }
    }
    for (final object in page.objects) {
      drawing.save();
      drawing.translate(
        object.x + object.width / 2,
        object.y + object.height / 2,
      );
      drawing.rotate(object.rotation);
      drawing.translate(-object.width / 2, -object.height / 2);
      if (object.kind == PageObjectKind.text) {
        final painter = TextPainter(
          text: TextSpan(
            text: object.text,
            style: TextStyle(
              color: Color(object.argb),
              fontSize: object.fontSize,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: object.width);
        painter.paint(drawing, Offset.zero);
        painter.dispose();
      } else {
        final image = await decode(await assets.read(object.assetId!));
        drawing.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(0, 0, object.width, object.height),
          Paint(),
        );
      }
      drawing.restore();
    }
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(
        (page.width * scale).ceil(),
        (page.height * scale).ceil(),
      );
      try {
        return (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  } finally {
    if (recorder.isRecording) recorder.endRecording().dispose();
    for (final image in images) {
      image.dispose();
    }
  }
}
