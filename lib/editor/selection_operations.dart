import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../document/notebook.dart';
import '../document/page_object.dart';
import '../document/notebook_recording.dart';
import 'stroke_geometry.dart';

class SelectionOperations {
  static Rect objectBounds(PageObject o) {
    final center = Offset(o.x + o.width / 2, o.y + o.height / 2);
    final c = math.cos(o.rotation).abs(), s = math.sin(o.rotation).abs();
    return Rect.fromCenter(
      center: center,
      width: o.width * c + o.height * s,
      height: o.width * s + o.height * c,
    );
  }

  static Rect? bounds(NotebookPage page, Set<String> ids) {
    Rect? result;
    void add(Rect r) {
      result = result?.expandToInclude(r) ?? r;
    }

    for (final s in page.strokes) {
      if (ids.contains(s.id)) add(StrokeGeometry.bounds(s));
    }
    for (final o in page.objects) {
      if (ids.contains(o.id)) add(objectBounds(o));
    }
    return result;
  }

  static Set<String> within(NotebookPage page, Rect rect) => {
    for (final s in page.strokes)
      if (StrokeGeometry.bounds(s).overlaps(rect)) s.id,
    for (final o in page.objects)
      if (objectBounds(o).overlaps(rect)) o.id,
  };
  static NotebookPage remove(NotebookPage page, Set<String> ids) =>
      page.copyWith(
        strokes: page.strokes.where((s) => !ids.contains(s.id)).toList(),
        objects: page.objects.where((o) => !ids.contains(o.id)).toList(),
      );
  static NotebookPage translate(
    NotebookPage page,
    Set<String> ids,
    Offset delta,
  ) {
    final r = bounds(page, ids);
    if (r == null) return page;
    // Content can be larger than the paper; keep at least its origin reachable.
    final dx = delta.dx.clamp(-r.left, math.max(-r.left, page.width - r.right));
    final dy = delta.dy.clamp(-r.top, math.max(-r.top, page.height - r.bottom));
    return page.copyWith(
      strokes: page.strokes
          .map(
            (s) => ids.contains(s.id)
                ? s.copyWith(
                    points: [
                      for (final p in s.points)
                        InkPoint(
                          x: p.x + dx,
                          y: p.y + dy,
                          pressure: p.pressure,
                        ),
                    ],
                  )
                : s,
          )
          .toList(),
      objects: page.objects
          .map(
            (o) =>
                ids.contains(o.id) ? o.copyWith(x: o.x + dx, y: o.y + dy) : o,
          )
          .toList(),
    );
  }

  static NotebookPage recolor(NotebookPage page, Set<String> ids, int color) =>
      page.copyWith(
        strokes: page.strokes
            .map((s) => ids.contains(s.id) ? s.copyWith(argb: color) : s)
            .toList(),
        objects: page.objects
            .map(
              (o) => ids.contains(o.id) && o.kind == PageObjectKind.text
                  ? o.copyWith(argb: color)
                  : o,
            )
            .toList(),
      );
  static NotebookPage scale(NotebookPage page, Set<String> ids, double factor) {
    if (!factor.isFinite || factor <= 0 || factor > 8) {
      throw ArgumentError.value(factor);
    }
    final r = bounds(page, ids);
    if (r == null) return page;
    final origin = r.topLeft;
    return page.copyWith(
      strokes: page.strokes
          .map(
            (s) => ids.contains(s.id)
                ? s.copyWith(
                    width: s.width * factor,
                    points: [
                      for (final p in s.points)
                        InkPoint(
                          x: origin.dx + (p.x - origin.dx) * factor,
                          y: origin.dy + (p.y - origin.dy) * factor,
                          pressure: p.pressure,
                        ),
                    ],
                  )
                : s,
          )
          .toList(),
      objects: page.objects
          .map(
            (o) => ids.contains(o.id)
                ? o.copyWith(
                    x: origin.dx + (o.x - origin.dx) * factor,
                    y: origin.dy + (o.y - origin.dy) * factor,
                    width: o.width * factor,
                    height: o.height * factor,
                    fontSize: o.fontSize * factor,
                  )
                : o,
          )
          .toList(),
    );
  }

  static NotebookPage rotate(
    NotebookPage page,
    Set<String> ids,
    double radians,
  ) {
    final r = bounds(page, ids);
    if (r == null) return page;
    Offset rotatePoint(Offset p) {
      final d = p - r.center;
      return r.center +
          Offset(
            d.dx * math.cos(radians) - d.dy * math.sin(radians),
            d.dx * math.sin(radians) + d.dy * math.cos(radians),
          );
    }

    return page.copyWith(
      strokes: page.strokes
          .map(
            (s) => ids.contains(s.id)
                ? s.copyWith(
                    points: s.points.map((p) {
                      final q = rotatePoint(Offset(p.x, p.y));
                      return InkPoint(x: q.dx, y: q.dy, pressure: p.pressure);
                    }).toList(),
                  )
                : s,
          )
          .toList(),
      objects: page.objects.map((o) {
        if (!ids.contains(o.id)) return o;
        final center = rotatePoint(
          Offset(o.x + o.width / 2, o.y + o.height / 2),
        );
        return o.copyWith(
          x: center.dx - o.width / 2,
          y: center.dy - o.height / 2,
          rotation: o.rotation + radians,
        );
      }).toList(),
    );
  }
}

class SelectionClipboard {
  static final _libraries = Expando<SelectionClipboard>();
  static SelectionClipboard forLibrary(Object key) =>
      _libraries[key] ??= SelectionClipboard();
  List<InkStroke> _strokes = [];
  List<PageObject> _objects = [];
  List<NotebookRecording> recordings = [];
  Rect? _bounds;
  bool get isEmpty => _strokes.isEmpty && _objects.isEmpty;
  String get text => _objects
      .where((o) => o.kind == PageObjectKind.text)
      .map((o) => o.text)
      .join('\n');
  void capture(
    NotebookPage page,
    Set<String> ids, {
    List<NotebookRecording> recordings = const [],
  }) {
    _strokes = page.strokes.where((s) => ids.contains(s.id)).toList();
    _objects = page.objects.where((o) => ids.contains(o.id)).toList();
    _bounds = SelectionOperations.bounds(page, ids);
    final references = _strokes
        .map((s) => s.audioRecordingId)
        .whereType<String>()
        .toSet();
    this.recordings = recordings
        .where((r) => references.contains(r.id))
        .toList();
  }

  NotebookPage paste(
    NotebookPage page,
    Offset position, {
    required String Function() newId,
  }) {
    if (isEmpty || _bounds == null) return page;
    final ids = <String>{};
    final available = recordings.map((r) => r.id).toSet();
    final strokes = _strokes.map((s) {
      final id = newId();
      ids.add(id);
      return available.contains(s.audioRecordingId)
          ? s.copyWith(id: id)
          : s.copyWith(id: id, audioRecordingId: null, audioOffsetMs: null);
    }).toList();
    final objects = _objects.map((o) {
      final id = newId();
      ids.add(id);
      return o.copyWith(id: id);
    }).toList();
    return SelectionOperations.translate(
      page.copyWith(
        strokes: [...page.strokes, ...strokes],
        objects: [...page.objects, ...objects],
      ),
      ids,
      position - _bounds!.topLeft,
    );
  }
}
