import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../document/notebook.dart';

enum PenButtonTool { none, pen, highlighter, eraser, selection }

enum PenButtonMode { hold, toggle }

class PenSettings {
  const PenSettings({
    this.pressure = 1,
    this.stabilization = 0,
    this.buttonTool = PenButtonTool.eraser,
    this.buttonMode = PenButtonMode.hold,
  });
  final double pressure, stabilization;
  final PenButtonTool buttonTool;
  final PenButtonMode buttonMode;
  EditorTool? get shortcutTool => switch (buttonTool) {
    PenButtonTool.none => null,
    PenButtonTool.pen => EditorTool.pen,
    PenButtonTool.highlighter => EditorTool.highlighter,
    PenButtonTool.eraser => EditorTool.eraser,
    PenButtonTool.selection => EditorTool.selection,
  };
  Map<String, Object> toJson() => {
    'pressure': pressure,
    'stabilization': stabilization,
    'buttonTool': buttonTool.name,
    'buttonMode': buttonMode.name,
  };
  factory PenSettings.fromJson(Map data) {
    double number(String name, double fallback, double max) {
      final value = data[name];
      return value is num && value.isFinite && value >= 0 && value <= max
          ? value.toDouble()
          : fallback;
    }

    return PenSettings(
      pressure: number('pressure', 1, 1),
      stabilization: number('stabilization', 0, .4),
      buttonTool: PenButtonTool.values.firstWhere(
        (v) => v.name == data['buttonTool'],
        orElse: () => PenButtonTool.eraser,
      ),
      buttonMode: PenButtonMode.values.firstWhere(
        (v) => v.name == data['buttonMode'],
        orElse: () => PenButtonMode.hold,
      ),
    );
  }
}

class PenPreferencesController {
  PenPreferencesController._(this.file, this.value);
  final File file;
  PenSettings value;
  Future<void> _writes = Future.value();
  static Future<PenPreferencesController> open(String root) async {
    final file = File(p.join(root, 'pen.json'));
    var value = const PenSettings();
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map) value = PenSettings.fromJson(data);
    } on FileSystemException {
      /* First launch or unavailable preference file. */
    } on FormatException {
      /* Interrupted/invalid preferences recover safely. */
    }
    return PenPreferencesController._(file, value);
  }

  Future<void> update(PenSettings settings) {
    // Validate callers as well as persisted data; the dialog isn't the only caller.
    final snapshot = value = PenSettings.fromJson(settings.toJson());
    return _writes = _writes.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      final staged = File('${file.path}.new');
      await staged.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      await staged.rename(file.path);
    });
  }
}
