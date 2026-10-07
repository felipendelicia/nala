import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/editor/draft_ink.dart';
import 'package:apuntes/editor/stroke_geometry.dart';

Future<ui.Image> render(DraftInk ink) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  DraftInkPainter(ink).paint(canvas, const Size(600, 600));
  final picture = recorder.endRecording();
  final image = await picture.toImage(600, 600);
  picture.dispose();
  return image;
}

Future<int> alpha(ui.Image image, int x, int y) async {
  final bytes = (await image.toByteData())!;
  return bytes.getUint8((y * image.width + x) * 4 + 3);
}

void main() {
  test('la presión de la muestra actual responde sin filtro retardado', () {
    final ink = DraftInk();
    ink.begin(
      const InkPoint(x: 10, y: 10, pressure: .1),
      tool: InkTool.pen,
      argb: 0xff000000,
      width: 4,
      stabilization: 0,
    );
    ink.add(const InkPoint(x: 20, y: 10, pressure: 1));
    final stroke = ink.finish('pressure')!;
    expect(stroke.points.last.pressure, 1);
    expect(StrokeGeometry.bounds(stroke).right, closeTo(23, .001));
    ink.dispose();
  });
  test('la punta por defecto coincide con la posición real', () {
    final ink = DraftInk();
    ink.begin(
      const InkPoint(x: 0, y: 0, pressure: 1),
      tool: InkTool.pen,
      argb: 0xff000000,
      width: 2,
    );
    ink.add(const InkPoint(x: 30, y: 40, pressure: 1));
    expect(ink.points.last.x, 30);
    expect(ink.points.last.y, 40);
    ink.dispose();
  });
  test(
    'al ampliar la hoja la tinta activa mantiene resolución de pantalla',
    () async {
      final ink = DraftInk();
      ink.begin(
        const InkPoint(x: 5, y: 13.37, pressure: 1),
        tool: InkTool.pen,
        argb: 0xff000000,
        width: .5,
        pressureCurve: PressureCurve.uniform,
        stabilization: 0,
        rasterBounds: const Rect.fromLTWH(0, 0, 64, 64),
        rasterScale: 8,
      );
      ink.add(const InkPoint(x: 50, y: 13.37, pressure: 1));
      Future<ui.Image> picture(bool raster) async {
        final r = ui.PictureRecorder();
        final canvas = Canvas(r)..scale(8);
        if (raster) {
          ink.paint(canvas);
        } else {
          canvas.drawPath(ink.path, Paint()..color = Colors.black);
        }
        final p = r.endRecording();
        final image = await p.toImage(512, 512);
        p.dispose();
        return image;
      }

      final live = await picture(true), vector = await picture(false);
      var difference = 0;
      for (var y = 100; y < 114; y++) {
        difference +=
            ((await alpha(live, 200, y)) - (await alpha(vector, 200, y))).abs();
      }
      expect(
        difference,
        lessThan(120),
        reason: 'Un zoom alto no debe ampliar una máscara de baja resolución.',
      );
      live.dispose();
      vector.dispose();
      ink.dispose();
    },
  );
  test('resaltador conserva opacidad al cruzar y repintar costuras', () async {
    final ink = DraftInk();
    ink.begin(
      const InkPoint(x: 30, y: 256, pressure: 1),
      tool: InkTool.highlighter,
      argb: 0xffffff00,
      width: 20,
      stabilization: 0,
      rasterBounds: const Rect.fromLTWH(0, 0, 600, 600),
    );
    for (var x = 32; x < 570; x += 2) {
      ink.add(InkPoint(x: x.toDouble(), y: 256, pressure: .3));
      if (x % 64 == 0) (await render(ink)).dispose();
    }
    ink.add(const InkPoint(x: 256, y: 100, pressure: 1));
    ink.add(const InkPoint(x: 256, y: 500, pressure: 1));
    final image = await render(ink);
    for (final point in [
      const Offset(255, 256),
      const Offset(256, 256),
      const Offset(257, 256),
      const Offset(100, 256),
      const Offset(256, 400),
    ]) {
      expect(await alpha(image, point.dx.toInt(), point.dy.toInt()), 85);
    }
    image.dispose();
    ink.cancel();
    ink.begin(
      const InkPoint(x: 100, y: 100, pressure: 1),
      tool: InkTool.pen,
      argb: 0xff000000,
      width: 4,
      rasterBounds: const Rect.fromLTWH(0, 0, 600, 600),
    );
    final fresh = await render(ink);
    expect(
      await alpha(fresh, 256, 256),
      0,
      reason: 'No quedan mosaicos del trazo anterior.',
    );
    expect(await alpha(fresh, 100, 100), 255);
    fresh.dispose();
    ink.dispose();
  });
}
