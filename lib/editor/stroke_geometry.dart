import 'dart:math';
import 'dart:ui';
import '../document/notebook.dart';

class StrokeOutline {
  StrokeOutline(this.circles, this.polygons, this.svgPath);
  final List<Rect> circles;
  final List<List<Offset>> polygons;
  late final Path path = _canvasPath();
  final String svgPath;
  Path _canvasPath() {
    final result = Path();
    for (final circle in circles) {
      result.addOval(circle);
    }
    for (final polygon in polygons) {
      result.addPolygon(polygon, true);
    }
    return result;
  }
}

class StrokeGeometry {
  static bool hitSweep(
    InkStroke stroke,
    Point<double> from,
    Point<double> to,
    double radius,
  ) {
    for (var i = 0; i < stroke.points.length; i++) {
      final p = stroke.points[i], previous = stroke.points[i == 0 ? 0 : i - 1];
      final a = Point(previous.x, previous.y), b = Point(p.x, p.y);
      final distance = _segmentDistance(a, b, from, to);
      if (distance <=
          radius +
              max(
                    widthFor(stroke.width, previous.pressure),
                    widthFor(stroke.width, p.pressure),
                  ) /
                  2) {
        return true;
      }
    }
    return false;
  }

  static double _pointDistance(
    Point<double> p,
    Point<double> a,
    Point<double> b,
  ) {
    final dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy;
    final t = length == 0
        ? 0.0
        : (((p.x - a.x) * dx + (p.y - a.y) * dy) / length).clamp(0, 1);
    return p.distanceTo(Point(a.x + dx * t, a.y + dy * t));
  }

  static double _segmentDistance(
    Point<double> a,
    Point<double> b,
    Point<double> c,
    Point<double> d,
  ) {
    double cross(Point<double> a, Point<double> b, Point<double> c) =>
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    if (max(min(a.x, b.x), min(c.x, d.x)) <=
            min(max(a.x, b.x), max(c.x, d.x)) &&
        max(min(a.y, b.y), min(c.y, d.y)) <=
            min(max(a.y, b.y), max(c.y, d.y)) &&
        cross(a, b, c) * cross(a, b, d) <= 0 &&
        cross(c, d, a) * cross(c, d, b) <= 0) {
      return 0;
    }
    return min(
      min(_pointDistance(a, c, d), _pointDistance(b, c, d)),
      min(_pointDistance(c, a, b), _pointDistance(d, a, b)),
    );
  }

  static final Expando<StrokeOutline> _cache = Expando();
  static double widthFor(double base, double pressure) =>
      base * (.35 + .65 * pressure.clamp(0, 1));
  static bool hitTest(InkStroke stroke, Point<double> point, double radius) {
    for (var i = 0; i < stroke.points.length; i++) {
      final p = stroke.points[i];
      final start = i == 0 ? p : stroke.points[i - 1];
      final dx = p.x - start.x, dy = p.y - start.y;
      final length = dx * dx + dy * dy;
      final t = length == 0
          ? 0.0
          : (((point.x - start.x) * dx + (point.y - start.y) * dy) / length)
                .clamp(0, 1);
      final distance = Point(
        start.x + t * dx,
        start.y + t * dy,
      ).distanceTo(point);
      final width = widthFor(
        stroke.width,
        start.pressure + t * (p.pressure - start.pressure),
      );
      if (distance <= radius + width / 2) return true;
    }
    return false;
  }

  static InkStroke translate(InkStroke stroke, double dx, double dy) =>
      stroke.copyWith(
        points: stroke.points
            .map(
              (p) => InkPoint(x: p.x + dx, y: p.y + dy, pressure: p.pressure),
            )
            .toList(),
      );
  static Rect bounds(InkStroke stroke) {
    var left = double.infinity,
        top = double.infinity,
        right = double.negativeInfinity,
        bottom = double.negativeInfinity;
    for (final p in stroke.points) {
      final r = widthFor(stroke.width, p.pressure) / 2;
      left = min(left, p.x - r);
      top = min(top, p.y - r);
      right = max(right, p.x + r);
      bottom = max(bottom, p.y + r);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static StrokeOutline outline(InkStroke stroke) =>
      _cache[stroke] ??= _build(stroke);
  static StrokeOutline _build(InkStroke stroke) {
    final circles = <Rect>[];
    final polygons = <List<Offset>>[];
    final svg = StringBuffer();
    for (var i = 0; i < stroke.points.length; i++) {
      final p = stroke.points[i],
          r = widthFor(stroke.width, stroke.points[i].pressure) / 2;
      circles.add(Rect.fromCircle(center: Offset(p.x, p.y), radius: r));
      svg.write(
        'M ${p.x + r} ${p.y} a $r $r 0 1 1 ${-2 * r} 0 a $r $r 0 1 1 ${2 * r} 0 Z ',
      );
      if (i == 0) continue;
      final a = stroke.points[i - 1];
      final length = sqrt(pow(p.x - a.x, 2) + pow(p.y - a.y, 2));
      if (length == 0) continue;
      final nx = -(p.y - a.y) / length,
          ny = (p.x - a.x) / length,
          ar = widthFor(stroke.width, a.pressure) / 2;
      final corners = [
        Offset(a.x - nx * ar, a.y - ny * ar),
        Offset(p.x - nx * r, p.y - ny * r),
        Offset(p.x + nx * r, p.y + ny * r),
        Offset(a.x + nx * ar, a.y + ny * ar),
      ];
      polygons.add(corners);
      svg.write('M ${corners[0].dx} ${corners[0].dy} ');
      for (final c in corners.skip(1)) {
        svg.write('L ${c.dx} ${c.dy} ');
      }
      svg.write('Z ');
    }
    return StrokeOutline(circles, polygons, svg.toString());
  }

  static String svg(NotebookPage page) {
    final out = StringBuffer(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${page.width}" height="${page.height}" viewBox="0 0 ${page.width} ${page.height}">',
    );
    final pattern = page.background.pattern;
    if (pattern != null) {
      out.write(
        '<rect width="${page.width}" height="${page.height}" fill="#ffffff"/>',
      );
      if (pattern == PaperPattern.grid || pattern == PaperPattern.ruled) {
        for (var y = 20; y < page.height; y += 20) {
          out.write(
            '<path d="M0 $y H${page.width}" stroke="#dbe3dc" stroke-width="0.6"/>',
          );
        }
      }
      if (pattern == PaperPattern.grid) {
        for (var x = 20; x < page.width; x += 20) {
          out.write(
            '<path d="M$x 0 V${page.height}" stroke="#dbe3dc" stroke-width="0.6"/>',
          );
        }
      }
      if (pattern == PaperPattern.dots) {
        for (var x = 20; x < page.width; x += 20) {
          for (var y = 20; y < page.height; y += 20) {
            out.write('<circle cx="$x" cy="$y" r="0.8" fill="#dbe3dc"/>');
          }
        }
      }
    }
    for (final stroke in page.strokes) {
      final color = (stroke.argb & 0xffffff).toRadixString(16).padLeft(6, '0');
      final alpha = stroke.tool == InkTool.highlighter
          ? 1 / 3
          : ((stroke.argb >> 24) & 0xff) / 255;
      out.write(
        '<path d="${outline(stroke).svgPath}" fill="#$color" fill-opacity="$alpha"/>',
      );
    }
    return '$out</svg>';
  }
}
