import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;

import '../document/asset_store.dart';
import '../document/notebook.dart';
import '../document/page_object.dart';
import '../editor/markdown_sheet.dart';
import '../editor/paper_background.dart';
import '../editor/paper_canvas.dart' show InkPainter;

/// Composes one notebook page. The caller owns [pdfBackground] and the result.
Future<ui.Image> rasterizeExportPage(
  NotebookPage page,
  AssetStore assets,
  int pixelWidth,
  int pixelHeight, {
  ui.Image? pdfBackground,
}) async {
  final size = ui.Size(page.width, page.height);
  if (!size.isFinite || size.isEmpty || pixelWidth <= 0 || pixelHeight <= 0) {
    throw ArgumentError('Las dimensiones de la hoja no son válidas.');
  }
  final bounds = ui.Offset.zero & size;
  final scaleX = pixelWidth / size.width;
  final scaleY = pixelHeight / size.height;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawColor(const ui.Color(0xffffffff), ui.BlendMode.src)
    ..scale(scaleX, scaleY)
    ..clipRect(bounds, doAntiAlias: false);
  final images = <({String assetId, int width, int height}), ui.Image>{};
  try {
    Future<ui.Image> storedImage(String assetId, ui.Size logicalSize) async {
      final width = math.min(pixelWidth, logicalSize.width * scaleX).ceil();
      final height = math.min(pixelHeight, logicalSize.height * scaleY).ceil();
      final key = (
        assetId: assetId,
        width: math.max(1, width),
        height: math.max(1, height),
      );
      if (images[key] case final cached?) return cached;

      final codec = await ui.instantiateImageCodec(
        await assets.read(assetId),
        targetWidth: key.width,
        targetHeight: key.height,
        allowUpscaling: false,
      );
      try {
        final frame = await codec.getNextFrame();
        return images[key] = frame.image;
      } finally {
        codec.dispose();
      }
    }

    final background = page.background;
    if (background.pattern case final pattern?) {
      PaperBackgroundPainter(pattern).paint(canvas, size);
    } else if (background.isImage) {
      _drawImage(canvas, await storedImage(background.assetId!, size), bounds);
    } else if (background.isPdf) {
      if (pdfBackground == null) {
        throw StateError('No se pudo preparar el fondo PDF.');
      }
      _drawImage(canvas, pdfBackground, bounds);
    }

    if (page.markdown case final markdown?) {
      paintMarkdownSheet(canvas, markdown, size);
    }
    for (final object in page.objects) {
      if (object.opacity == 0) continue;
      final objectSize = ui.Size(object.width, object.height);
      final image = object.kind == PageObjectKind.text
          ? null
          : await storedImage(object.assetId!, objectSize);
      _paintObject(canvas, object, objectSize, image);
    }
    InkPainter(page.strokes).paint(canvas, size);
    _paintComments(canvas, page, size);

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(pixelWidth, pixelHeight);
    } finally {
      picture.dispose();
    }
  } finally {
    if (recorder.isRecording) recorder.endRecording().dispose();
    for (final image in images.values) {
      image.dispose();
    }
  }
}

void _drawImage(ui.Canvas canvas, ui.Image image, ui.Rect target) {
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    target,
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
}

void _paintObject(
  ui.Canvas canvas,
  PageObject object,
  ui.Size size,
  ui.Image? image,
) {
  final bounds = ui.Offset.zero & size;
  final saveCount = canvas.getSaveCount();
  canvas.save();
  try {
    canvas
      ..translate(object.x + size.width / 2, object.y + size.height / 2)
      ..rotate(object.rotation)
      ..translate(-size.width / 2, -size.height / 2)
      ..clipRect(bounds, doAntiAlias: false);
    if (object.opacity != 1) {
      canvas.saveLayer(
        bounds,
        ui.Paint()
          ..color = const ui.Color(
            0xffffffff,
          ).withValues(alpha: object.opacity),
      );
    }
    if (image != null) {
      _drawImage(canvas, image, bounds);
    } else {
      final text = TextPainter(
        text: TextSpan(
          text: object.text,
          style: TextStyle(
            fontFamily: 'NalaSans',
            fontSize: object.fontSize,
            height: 1.2,
            color: ui.Color(object.argb),
            decoration: object.link == null
                ? null
                : ui.TextDecoration.underline,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      try {
        text.layout(maxWidth: size.width);
        text.paint(canvas, ui.Offset.zero);
      } finally {
        text.dispose();
      }
    }
  } finally {
    canvas.restoreToCount(saveCount);
  }
}

void _paintComments(ui.Canvas canvas, NotebookPage page, ui.Size size) {
  final radius = math.min(9.0, math.min(size.width, size.height) / 2);
  final marker = ui.Paint()..color = const ui.Color(0xff24584b);
  for (var i = 0; i < page.comments.length; i++) {
    final comment = page.comments[i];
    final center = ui.Offset(
      comment.x.clamp(radius, size.width - radius).toDouble(),
      comment.y.clamp(radius, size.height - radius).toDouble(),
    );
    canvas.drawCircle(center, radius, marker);
    final label = TextPainter(
      text: TextSpan(
        text: '${i + 1}',
        style: const TextStyle(
          fontFamily: 'NalaSans',
          color: ui.Color(0xffffffff),
          fontSize: 10,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    try {
      label.layout();
      label.paint(
        canvas,
        center - ui.Offset(label.width / 2, label.height / 2),
      );
    } finally {
      label.dispose();
    }
  }
}
