import 'package:flutter/material.dart';
import '../document/notebook.dart';

class PaperBackgroundPainter extends CustomPainter {
  PaperBackgroundPainter(this.pattern);
  final PaperPattern pattern;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final lines = Paint()..color = const Color(0xffdbe3dc)..strokeWidth = .6;
    const step = 20.0;
    if (pattern == PaperPattern.grid || pattern == PaperPattern.ruled) {
      for (double y = step; y < size.height; y += step) canvas.drawLine(Offset(0, y), Offset(size.width, y), lines);
    }
    if (pattern == PaperPattern.grid) {
      for (double x = step; x < size.width; x += step) canvas.drawLine(Offset(x, 0), Offset(x, size.height), lines);
    }
    if (pattern == PaperPattern.dots) {
      for (double y = step; y < size.height; y += step) {
        for (double x = step; x < size.width; x += step) canvas.drawCircle(Offset(x, y), .8, lines);
      }
    }
  }
  @override
  bool shouldRepaint(PaperBackgroundPainter oldDelegate) => pattern != oldDelegate.pattern;
}
