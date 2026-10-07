import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../document/notebook.dart';

class PenFavorite {
  PenFavorite({
    required this.id,
    required this.name,
    required this.tool,
    required this.argb,
    required this.width,
  }) {
    nonEmpty(id);
    nonEmpty(name);
    finiteNumber(width, positive: true, max: 80);
    if ((tool != EditorTool.pen && tool != EditorTool.highlighter) ||
        argb < 0 ||
        argb > 0xffffffff) {
      throw const FormatException('Lápiz favorito inválido');
    }
  }
  final String id, name;
  final EditorTool tool;
  final int argb;
  final double width;
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'tool': tool.name,
    'argb': argb,
    'width': width,
  };
  factory PenFavorite.fromJson(Map<String, dynamic> data) => PenFavorite(
    id: data['id'] as String,
    name: data['name'] as String,
    tool: EditorTool.values.byName(data['tool'] as String),
    argb: data['argb'] as int,
    width: (data['width'] as num).toDouble(),
  );
}

class PenFavoritesController extends ChangeNotifier {
  PenFavoritesController._(this.file, this._values);
  final File file;
  List<PenFavorite> _values;
  List<PenFavorite> get values => List.unmodifiable(_values);
  Future<void> _writes = Future.value();
  static List<PenFavorite> defaults() => [
    PenFavorite(
      id: 'graphite',
      name: 'Grafito fino',
      tool: EditorTool.pen,
      argb: 0xff202020,
      width: 2.5,
    ),
    PenFavorite(
      id: 'correction',
      name: 'Rojo',
      tool: EditorTool.pen,
      argb: 0xffc14747,
      width: 2.5,
    ),
    PenFavorite(
      id: 'yellow',
      name: 'Resaltador amarillo',
      tool: EditorTool.highlighter,
      argb: 0xffe9ba3b,
      width: 14,
    ),
  ];
  static Future<PenFavoritesController> open(String root) async {
    final file = File('$root/pen-favorites.json');
    var values = defaults();
    try {
      final data = jsonDecode(await file.readAsString()) as List;
      values = data
          .map((d) => PenFavorite.fromJson(d as Map<String, dynamic>))
          .take(12)
          .toList();
    } on Object {
      /* Recover malformed or unavailable local preferences. */
    }
    return PenFavoritesController._(file, values);
  }

  Future<void> add(PenFavorite favorite) {
    if (_values.length >= 12 && !_values.any((f) => f.id == favorite.id)) {
      throw StateError('Podés guardar hasta doce lápices favoritos.');
    }
    _values = [..._values.where((f) => f.id != favorite.id), favorite];
    return _persist();
  }

  Future<void> remove(String id) {
    _values = _values.where((f) => f.id != id).toList();
    return _persist();
  }

  Future<void> _persist() {
    final snapshot = jsonEncode(_values.map((f) => f.toJson()).toList());
    notifyListeners();
    return _writes = _writes.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      final staged = File('${file.path}.new');
      await staged.writeAsString(snapshot, flush: true);
      await staged.rename(file.path);
    });
  }
}
