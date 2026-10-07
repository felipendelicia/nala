import 'package:flutter/material.dart';
import '../document/notebook.dart';

class PaperBackgroundPainter extends CustomPainter {
  PaperBackgroundPainter(this.pattern);
  final PaperPattern pattern;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final lines = Paint()
      ..color = const Color(0xffdbe3dc)
      ..strokeWidth = .6;
    const step = 20.0;
    for (final (from, to) in paperGuideLines(pattern, size)) {
      canvas.drawLine(from, to, lines);
    }
    if (pattern == PaperPattern.dots) {
      for (double y = step; y < size.height; y += step) {
        for (double x = step; x < size.width; x += step) {
          canvas.drawCircle(Offset(x, y), .8, lines);
        }
      }
    }
  }

  @override
  bool shouldRepaint(PaperBackgroundPainter oldDelegate) =>
      pattern != oldDelegate.pattern;
}

/// The same page coordinates are used by the canvas and exported PDFs.
Iterable<(Offset, Offset)> paperGuideLines(
  PaperPattern pattern,
  Size size,
) sync* {
  const step = 20.0;
  if (pattern == PaperPattern.grid || pattern == PaperPattern.ruled) {
    for (double y = step; y < size.height; y += step) {
      yield (Offset(0, y), Offset(size.width, y));
    }
  }
  if (pattern == PaperPattern.grid) {
    for (double x = step; x < size.width; x += step) {
      yield (Offset(x, 0), Offset(x, size.height));
    }
  }
  if (pattern == PaperPattern.cornell) {
    final margin = size.width * .06;
    final header = size.height * .10;
    final summary = size.height * .80;
    final cue = size.width * .28;
    yield (Offset(margin, header), Offset(size.width - margin, header));
    yield (Offset(margin, summary), Offset(size.width - margin, summary));
    yield (Offset(cue, header), Offset(cue, summary));
    for (double y = header + step; y < summary; y += step) {
      yield (Offset(cue, y), Offset(size.width - margin, y));
    }
    for (double y = summary + step; y < size.height - margin; y += step) {
      yield (Offset(margin, y), Offset(size.width - margin, y));
    }
  }
  if (pattern == PaperPattern.weekly) {
    final margin = size.width * .06;
    final header = size.height * .10;
    final bottom = size.height - margin;
    final row = (bottom - header) / 7;
    final dayColumn = size.width * .22;
    yield (Offset(margin, header), Offset(margin, bottom));
    yield (
      Offset(size.width - margin, header),
      Offset(size.width - margin, bottom),
    );
    yield (Offset(dayColumn, header), Offset(dayColumn, bottom));
    for (var day = 0; day <= 7; day++) {
      final y = header + row * day;
      yield (Offset(margin, y), Offset(size.width - margin, y));
    }
  }
}

String paperBackgroundSvg(PaperPattern pattern, Size size) {
  final out = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" width="${size.width}" height="${size.height}" viewBox="0 0 ${size.width} ${size.height}">'
    '<rect width="${size.width}" height="${size.height}" fill="#ffffff"/>',
  );
  for (final (from, to) in paperGuideLines(pattern, size)) {
    out.write(
      '<path d="M${from.dx} ${from.dy} L${to.dx} ${to.dy}" stroke="#dbe3dc" stroke-width="0.6"/>',
    );
  }
  if (pattern == PaperPattern.dots) {
    for (double y = 20; y < size.height; y += 20) {
      for (double x = 20; x < size.width; x += 20) {
        out.write('<circle cx="$x" cy="$y" r="0.8" fill="#dbe3dc"/>');
      }
    }
  }
  return '$out</svg>';
}
