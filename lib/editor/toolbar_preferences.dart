import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

enum ToolbarDock { top, left, right }

enum ToolbarAction {
  pen,
  highlighter,
  eraser,
  selection,
  color,
  width,
  penSettings,
  undo,
  redo,
  paper,
  applyPaper,
  text,
  image,
  latex,
  link,
  elements,
  templates,
  search,
  study,
  audio,
  deleteSelection,
}

const toolbarLabels = <ToolbarAction, String>{
  ToolbarAction.pen: 'Lápiz',
  ToolbarAction.highlighter: 'Resaltador',
  ToolbarAction.eraser: 'Borrador',
  ToolbarAction.selection: 'Selección',
  ToolbarAction.color: 'Color de tinta',
  ToolbarAction.width: 'Grosor de tinta',
  ToolbarAction.penSettings: 'Ajustes del lápiz',
  ToolbarAction.undo: 'Deshacer',
  ToolbarAction.redo: 'Rehacer',
  ToolbarAction.paper: 'Tipo de hoja',
  ToolbarAction.applyPaper: 'Aplicar hoja a todo el cuaderno',
  ToolbarAction.text: 'Insertar texto',
  ToolbarAction.image: 'Insertar imagen',
  ToolbarAction.latex: 'Insertar fórmula LaTeX',
  ToolbarAction.link: 'Enlace a otro apunte',
  ToolbarAction.elements: 'Elementos reutilizables',
  ToolbarAction.templates: 'Plantillas',
  ToolbarAction.search: 'Buscar en el apunte',
  ToolbarAction.study: 'Tarjetas de estudio',
  ToolbarAction.audio: 'Grabación de clase',
  ToolbarAction.deleteSelection: 'Eliminar selección',
};

const toolbarInkPalette = <int, String>{
  0xff202020: 'Grafito',
  0xff24584b: 'Verde',
  0xff284cad: 'Azul',
  0xffc14747: 'Rojo',
  0xffe9ba3b: 'Amarillo',
  0xff8553aa: 'Violeta',
};
const toolbarQuickColorLimit = 3;
const defaultToolbarQuickColors = [0xff202020, 0xff284cad, 0xffc14747];

class ToolbarLayout {
  ToolbarLayout({
    required List<ToolbarAction> order,
    required Set<ToolbarAction> visible,
    this.dock = ToolbarDock.top,
    Iterable<int> quickColors = defaultToolbarQuickColors,
  }) : order = List.unmodifiable(order),
       visible = Set.unmodifiable(visible),
       quickColors = List.unmodifiable(
         quickColors
             .where(toolbarInkPalette.containsKey)
             .toSet()
             .take(toolbarQuickColorLimit),
       ) {
    if (order.length != ToolbarAction.values.length ||
        order.toSet().length != order.length) {
      throw const FormatException('Orden de barra inválido');
    }
  }
  factory ToolbarLayout.defaults() => ToolbarLayout(
    order: ToolbarAction.values,
    visible: {...ToolbarAction.values.take(11), ToolbarAction.deleteSelection},
  );
  final List<ToolbarAction> order;
  final Set<ToolbarAction> visible;
  final ToolbarDock dock;
  final List<int> quickColors;
  ToolbarLayout copyWith({
    List<ToolbarAction>? order,
    Set<ToolbarAction>? visible,
    ToolbarDock? dock,
    Iterable<int>? quickColors,
  }) => ToolbarLayout(
    order: order ?? this.order,
    visible: visible ?? this.visible,
    dock: dock ?? this.dock,
    quickColors: quickColors ?? this.quickColors,
  );
  Map<String, Object> toJson() => {
    'version': 1,
    'dock': dock.name,
    'order': order.map((v) => v.name).toList(),
    'visible': visible.map((v) => v.name).toList(),
    'quickColors': quickColors,
  };
  factory ToolbarLayout.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Versión de barra inválida');
    }
    final storedColors = json['quickColors'];
    return ToolbarLayout(
      dock: ToolbarDock.values.byName(json['dock'] as String),
      order: (json['order'] as List)
          .map((v) => ToolbarAction.values.byName(v as String))
          .toList(),
      visible: (json['visible'] as List)
          .map((v) => ToolbarAction.values.byName(v as String))
          .toSet(),
      quickColors: storedColors is List
          ? storedColors.whereType<int>()
          : defaultToolbarQuickColors,
    );
  }
}

class ToolbarPreferencesController extends ChangeNotifier {
  ToolbarPreferencesController._(this.file, this._layout);
  final File file;
  ToolbarLayout _layout;
  ToolbarLayout get layout => _layout;
  Future<void> _writes = Future.value();
  static Future<ToolbarLayout> _read(File file) async {
    try {
      return ToolbarLayout.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } on Object {
      return ToolbarLayout.defaults();
    }
  }

  static Future<ToolbarPreferencesController> open(String root) async {
    final file = File('$root/toolbar.json');
    return ToolbarPreferencesController._(file, await _read(file));
  }

  Future<void> reload() async {
    await _writes;
    _layout = await _read(file);
    notifyListeners();
  }

  Future<void> update(ToolbarLayout layout) {
    _layout = layout;
    notifyListeners();
    return _writes = _writes.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      final staged = File('${file.path}.${const Uuid().v4()}.tmp');
      try {
        await staged.writeAsString(jsonEncode(layout.toJson()), flush: true);
        await staged.rename(file.path);
      } finally {
        if (await staged.exists()) await staged.delete();
      }
    });
  }
}
