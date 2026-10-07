import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import '../document/notebook.dart';
import '../document/page_object.dart';
import '../editor/selection_operations.dart';

/// A reusable group whose visible bounds start at the origin.
class LibraryElement {
  LibraryElement({
    required this.id,
    required String name,
    required this.width,
    required this.height,
    required List<InkStroke> strokes,
    required List<PageObject> objects,
  }) : name = _elementName(name),
       strokes = List.unmodifiable(strokes),
       objects = List.unmodifiable(objects) {
    nonEmpty(id);
    finiteNumber(width, positive: true);
    finiteNumber(height, positive: true);
    if (strokes.length + objects.length == 0 ||
        strokes.length + objects.length > maxItems) {
      throw const FormatException(
        'El elemento está vacío o es demasiado grande',
      );
    }
    final ids = <String>{};
    var pointCount = 0;
    for (final stroke in strokes) {
      if (!ids.add(stroke.id)) {
        throw const FormatException('Contenido de elemento duplicado');
      }
      // Constructors used by the editor permit live geometry. Persist only
      // complete, valid strokes and no references to another note's audio.
      InkStroke.fromJson(stroke.toJson());
      if (stroke.audioRecordingId != null || stroke.audioOffsetMs != null) {
        throw const FormatException('El elemento contiene una grabación');
      }
      pointCount += stroke.points.length;
      if (pointCount > maxPoints) {
        throw const FormatException('El elemento tiene demasiados puntos');
      }
    }
    for (final object in objects) {
      if (!ids.add(object.id)) {
        throw const FormatException('Contenido de elemento duplicado');
      }
    }
    final bounds = SelectionOperations.bounds(_page, ids);
    const tolerance = .00001;
    if (bounds == null ||
        !bounds.left.isFinite ||
        !bounds.top.isFinite ||
        !bounds.right.isFinite ||
        !bounds.bottom.isFinite ||
        bounds.left < -tolerance ||
        bounds.top < -tolerance ||
        bounds.right > width + tolerance ||
        bounds.bottom > height + tolerance) {
      throw const FormatException(
        'Contenido fuera de los límites del elemento',
      );
    }
  }

  static const maxItems = 10000, maxPoints = 250000;
  final String id, name;
  final double width, height;
  final List<InkStroke> strokes;
  final List<PageObject> objects;

  Set<String> get assetIds => {
    for (final object in objects) ...[
      if (object.assetId != null) object.assetId!,
      if (object.originalAssetId != null) object.originalAssetId!,
    ],
  };

  NotebookPage get _page => NotebookPage(
    id: id,
    width: width,
    height: height,
    background: const PageBackground.paper(PaperPattern.blank),
    strokes: strokes,
    objects: objects,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'width': width,
    'height': height,
    'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
    'objects': objects.map((object) => object.toJson()).toList(),
  };

  factory LibraryElement.fromJson(Map<String, dynamic> value) {
    try {
      final strokes = value['strokes'] as List;
      final objects = value['objects'] as List;
      if (strokes.length + objects.length > maxItems) {
        throw const FormatException('El elemento es demasiado grande');
      }
      var pointCount = 0;
      for (final stroke in strokes) {
        pointCount += ((stroke as Map)['points'] as List).length;
        if (pointCount > maxPoints) {
          throw const FormatException('El elemento tiene demasiados puntos');
        }
      }
      return LibraryElement(
        id: nonEmpty(value['id']),
        name: value['name'] as String,
        width: finiteNumber(value['width'], positive: true),
        height: finiteNumber(value['height'], positive: true),
        strokes: strokes
            .map((stroke) => InkStroke.fromJson(stroke as Map<String, dynamic>))
            .toList(),
        objects: objects
            .map(
              (object) => PageObject.fromJson(object as Map<String, dynamic>),
            )
            .toList(),
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Elemento dañado');
    }
  }
}

/// Persistent per-library registry. All instances and backup operations share
/// one queue, so a second editor cannot overwrite another editor's changes.
class ElementStore {
  ElementStore({required this.root});
  final String root;
  static const maxRegistryBytes = 8 * 1024 * 1024, maxElements = 1000;
  static final Map<String, Future<void>> _queues = {};
  static final Map<String, ValueNotifier<int>> _signals = {};
  static String _registryPath(String root) => path.normalize(
    path.absolute(path.join(root, 'elements', 'registry.json')),
  );
  File get _file => File(_registryPath(root));
  ValueListenable<int> get changes =>
      _signals.putIfAbsent(_registryPath(root), () => ValueNotifier(0));

  /// The callback operates directly on the registry; do not call another
  /// queued ElementStore method from inside it. Used by coherent backups.
  static Future<T> withRegistryLock<T>(
    String root,
    Future<T> Function() operation,
  ) {
    final key = _registryPath(root);
    final result = (_queues[key] ?? Future<void>.value()).then((_) async {
      final value = await operation();
      final signal = _signals[key];
      if (signal != null) signal.value++;
      return value;
    });
    _queues[key] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  static List<LibraryElement> validateRegistry(String json) {
    if (utf8.encode(json).length > maxRegistryBytes) {
      throw const FormatException(
        'La biblioteca de elementos es demasiado grande',
      );
    }
    try {
      final value = jsonDecode(json) as Map<String, dynamic>;
      if (value['version'] != 1) {
        throw const FormatException('Biblioteca de elementos no compatible');
      }
      final elements = value['elements'] as List;
      if (elements.length > maxElements) {
        throw const FormatException(
          'Hay demasiados elementos en la biblioteca',
        );
      }
      final ids = <String>{};
      final result = <LibraryElement>[];
      for (final value in elements) {
        final element = LibraryElement.fromJson(value as Map<String, dynamic>);
        if (!ids.add(element.id)) {
          throw const FormatException('Elemento duplicado');
        }
        result.add(element);
      }
      return List.unmodifiable(result);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Biblioteca de elementos dañada');
    }
  }

  Future<List<LibraryElement>> _read() async {
    if (!await _file.exists()) return [];
    if (await _file.length() > maxRegistryBytes) {
      throw const FormatException(
        'La biblioteca de elementos es demasiado grande',
      );
    }
    return validateRegistry(await _file.readAsString());
  }

  Future<List<LibraryElement>> load({String query = ''}) async {
    await (_queues[_registryPath(root)] ?? Future<void>.value());
    final key = query.trim().toLowerCase();
    final elements = await _read();
    return List.unmodifiable(
      elements.where(
        (element) => key.isEmpty || element.name.toLowerCase().contains(key),
      ),
    );
  }

  Future<void> _write(List<LibraryElement> elements) async {
    final json = jsonEncode({
      'version': 1,
      'elements': elements.map((element) => element.toJson()).toList(),
    });
    validateRegistry(json);
    await _file.parent.create(recursive: true);
    final temporary = File('${_file.path}.${const Uuid().v4()}.tmp');
    try {
      await temporary.writeAsString(json, flush: true);
      await temporary.rename(_file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _mutate(
    List<LibraryElement> Function(List<LibraryElement>) change,
  ) => withRegistryLock(root, () async {
    await _write(change(await _read()));
  });

  Future<LibraryElement> saveSelection({
    required String name,
    required NotebookPage page,
    required Set<String> ids,
  }) async {
    final bounds = SelectionOperations.bounds(page, ids);
    if (bounds == null) {
      throw const FormatException(
        'Seleccioná trazos u objetos para guardarlos',
      );
    }
    final element = LibraryElement(
      id: const Uuid().v4(),
      name: name,
      width: bounds.width,
      height: bounds.height,
      strokes: [
        for (final stroke in page.strokes)
          if (ids.contains(stroke.id))
            stroke.copyWith(
              audioRecordingId: null,
              audioOffsetMs: null,
              points: [
                for (final point in stroke.points)
                  InkPoint(
                    x: point.x - bounds.left,
                    y: point.y - bounds.top,
                    pressure: point.pressure,
                  ),
              ],
            ),
      ],
      objects: [
        for (final object in page.objects)
          if (ids.contains(object.id))
            object.copyWith(
              x: object.x - bounds.left,
              y: object.y - bounds.top,
            ),
      ],
    );
    await _mutate((elements) => [...elements, element]);
    return element;
  }

  Future<void> rename(String id, String name) async {
    final normalized = _elementName(name);
    await _mutate((elements) {
      if (!elements.any((element) => element.id == id)) {
        throw StateError('Ese elemento ya no está disponible');
      }
      return [
        for (final element in elements)
          if (element.id == id)
            LibraryElement(
              id: element.id,
              name: normalized,
              width: element.width,
              height: element.height,
              strokes: element.strokes,
              objects: element.objects,
            )
          else
            element,
      ];
    });
  }

  Future<void> remove(String id) async {
    nonEmpty(id);
    await _mutate(
      (elements) => elements.where((element) => element.id != id).toList(),
    );
  }

  /// Fits a group without enlarging it. Position names the visible top-left,
  /// including rotated objects and the ink's pressure-dependent outline.
  NotebookPage insert(
    LibraryElement element,
    NotebookPage page,
    Offset position, {
    required String Function() newId,
  }) {
    finiteNumber(page.width, positive: true);
    finiteNumber(page.height, positive: true);
    finiteNumber(position.dx);
    finiteNumber(position.dy);
    final factor = math.min(
      1.0,
      math.min(page.width / element.width, page.height / element.height),
    );
    final x = position.dx.clamp(
      0.0,
      math.max(0.0, page.width - element.width * factor),
    );
    final y = position.dy.clamp(
      0.0,
      math.max(0.0, page.height - element.height * factor),
    );
    final usedIds = {
      ...page.strokes.map((stroke) => stroke.id),
      ...page.objects.map((object) => object.id),
    };
    String nextId() {
      final id = nonEmpty(newId());
      if (!usedIds.add(id)) {
        throw const FormatException('Identificador de contenido duplicado');
      }
      return id;
    }

    return page.copyWith(
      strokes: [
        ...page.strokes,
        for (final stroke in element.strokes)
          stroke.copyWith(
            id: nextId(),
            width: stroke.width * factor,
            audioRecordingId: null,
            audioOffsetMs: null,
            points: [
              for (final point in stroke.points)
                InkPoint(
                  x: x + point.x * factor,
                  y: y + point.y * factor,
                  pressure: point.pressure,
                ),
            ],
          ),
      ],
      objects: [
        ...page.objects,
        for (final object in element.objects)
          object.copyWith(
            id: nextId(),
            locked: false,
            x: x + object.x * factor,
            y: y + object.y * factor,
            width: object.width * factor,
            height: object.height * factor,
            fontSize: object.fontSize * factor,
          ),
      ],
    );
  }
}

String _elementName(String value) {
  final name = value.trim();
  if (name.isEmpty || name.length > 120) {
    throw const FormatException('Usá un nombre de 1 a 120 caracteres');
  }
  return name;
}
