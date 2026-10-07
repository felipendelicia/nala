import 'dart:math' as math;
import 'dart:ui';
import '../document/notebook.dart';

/// Immutable document geometry; only visible pages need a widget or PDF raster.
class PageLayout {
  PageLayout(List<NotebookPage> pages) {
    width = pages.fold(0.0, (value, page) => math.max(value, page.width));
    var top = 0.0;
    for (final page in pages) {
      _rects.add(
        Rect.fromLTWH((width - page.width) / 2, top, page.width, page.height),
      );
      top += page.height + gap;
    }
    height = math.max(0, top - gap);
  }
  static const gap = 32.0;
  final _rects = <Rect>[];
  late final double width, height;
  Rect rect(int index) => _rects[index];
  int _at(double y) {
    var lo = 0, hi = _rects.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_rects[mid].bottom < y) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  List<int> visible(Rect viewport) {
    final result = <int>[];
    for (
      var i = _at(viewport.top);
      i < _rects.length && _rects[i].top <= viewport.bottom;
      i++
    ) {
      if (_rects[i].overlaps(viewport)) result.add(i);
    }
    return result;
  }

  int? hit(Offset position) {
    final i = _at(position.dy);
    return i < _rects.length && _rects[i].contains(position) ? i : null;
  }

  int nearest(double y) {
    final i = _at(y).clamp(0, _rects.length - 1);
    if (i > 0 &&
        y < _rects[i].top &&
        y - _rects[i - 1].bottom < _rects[i].top - y) {
      return i - 1;
    }
    return i;
  }
}
