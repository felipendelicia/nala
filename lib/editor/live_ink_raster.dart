import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui';

/// A transparent, opaque-white mask for one active stroke. Only tiles touched
/// since the last frame receive new geometry. Stroke alpha is applied once when
/// compositing the mask, including at crossings and shared tile edges.
class LiveInkRaster {
  LiveInkRaster({required this.bounds, required double scale})
    : scale = math.min(
        scale.clamp(.1, 3),
        math.sqrt(8000000 / math.max(1, bounds.width * bounds.height)),
      );
  final Rect bounds;
  final double scale;
  static const tileSize = 256.0;
  final _tiles = <(int, int), _Tile>{};

  void add(Path segment) {
    final area = segment.getBounds().inflate(1).intersect(bounds);
    if (area.isEmpty) return;
    for (
      var y = (area.top / tileSize).floor();
      y <= (area.bottom / tileSize).floor();
      y++
    ) {
      for (
        var x = (area.left / tileSize).floor();
        x <= (area.right / tileSize).floor();
        x++
      ) {
        final tile = _tiles.putIfAbsent(
          (x, y),
          () => _Tile(
            Rect.fromLTWH(
              x * tileSize,
              y * tileSize,
              tileSize,
              tileSize,
            ).intersect(bounds),
          ),
        );
        tile.pending.addPath(segment, Offset.zero);
        tile.dirty = true;
      }
    }
  }

  void paint(Canvas canvas, Color color) {
    Timeline.startSync('Nala live ink tiles');
    try {
      final ink = Paint()
        ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn)
        ..filterQuality = FilterQuality.low;
      for (final tile in _tiles.values) {
        if (tile.bounds.isEmpty) continue;
        if (tile.dirty) tile.rasterize(scale);
        final image = tile.image;
        if (image == null) continue;
        // The padded image supplies edge samples when magnified. Draw only the
        // non-overlapping core; neighboring tiles never accumulate marker alpha.
        final source = Rect.fromLTWH(
          2,
          2,
          tile.bounds.width * scale,
          tile.bounds.height * scale,
        );
        canvas.drawImageRect(image, source, tile.bounds, ink);
      }
    } finally {
      Timeline.finishSync();
    }
  }

  void dispose() {
    for (final tile in _tiles.values) {
      tile.image?.dispose();
    }
    _tiles.clear();
  }
}

class _Tile {
  _Tile(this.bounds);
  final Rect bounds;
  Path pending = Path();
  bool dirty = false;
  Image? image;
  void rasterize(double scale) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final previous = image;
    if (previous != null) canvas.drawImage(previous, Offset.zero, Paint());
    canvas.translate(2, 2);
    canvas.scale(scale);
    canvas.translate(-bounds.left, -bounds.top);
    canvas.drawPath(pending, Paint()..color = const Color(0xffffffff));
    final picture = recorder.endRecording();
    image = picture.toImageSync(
      (bounds.width * scale).ceil() + 4,
      (bounds.height * scale).ceil() + 4,
    );
    picture.dispose();
    previous?.dispose();
    pending = Path();
    dirty = false;
  }
}
