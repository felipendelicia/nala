import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import '../document/asset_store.dart';
import '../document/notebook.dart';
import '../pdf/pdf_service.dart';

class PageTemplate {
  const PageTemplate({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.background,
    this.coverAssetId,
  });
  final String id, name;
  final double width, height;
  final PageBackground background;
  final String? coverAssetId;
  bool get builtIn => background.pattern != null;
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'width': width,
    'height': height,
    'background': background.toJson(),
    'coverAssetId': ?coverAssetId,
  };
  factory PageTemplate.fromJson(Map<String, dynamic> value) => PageTemplate(
    id: nonEmpty(value['id']),
    name: nonEmpty(value['name']),
    width: finiteNumber(value['width'], positive: true),
    height: finiteNumber(value['height'], positive: true),
    background: PageBackground.fromJson(
      value['background'] as Map<String, dynamic>,
    ),
    coverAssetId: value['coverAssetId'] == null
        ? null
        : validAssetId(value['coverAssetId']),
  );
}

class TemplateStore {
  TemplateStore({required this.root, required this.assets, required this.pdf});
  final String root;
  final AssetStore assets;
  final PdfService pdf;
  File get _file => File(path.join(root, 'templates', 'registry.json'));
  static final Map<String, Future<void>> _queues = {};
  Future<void> get _tail => _queues[_file.absolute.path] ?? Future.value();
  set _tail(Future<void> value) => _queues[_file.absolute.path] = value;
  static const _labels = {
    'blank': 'En blanco',
    'ruled': 'Rayada',
    'grid': 'Cuadriculada',
    'dots': 'Punteada',
    'cornell': 'Cornell',
    'weekly': 'Agenda semanal',
  };
  static List<PageTemplate> get builtIns => [
    for (final pattern in PaperPattern.values)
      PageTemplate(
        id: pattern.name,
        name: _labels[pattern.name] ?? pattern.name,
        width: 595.28,
        height: 841.89,
        background: PageBackground.paper(pattern),
      ),
  ];
  Future<List<PageTemplate>> load() async {
    await _tail;
    return [...builtIns, ...await _read()];
  }

  Future<List<PageTemplate>> _read() async {
    if (!await _file.exists()) return [];
    final data = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    if (data['version'] != 1) {
      throw const FormatException('Biblioteca de plantillas no compatible');
    }
    return (data['templates'] as List)
        .map((v) => PageTemplate.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  Future<void> _write(List<PageTemplate> templates) async {
    await _file.parent.create(recursive: true);
    final temp = File('${_file.path}.${const Uuid().v4()}.tmp');
    try {
      await temp.writeAsString(
        jsonEncode({
          'version': 1,
          'templates': templates.map((t) => t.toJson()).toList(),
        }),
        flush: true,
      );
      await temp.rename(_file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> _mutate(List<PageTemplate> Function(List<PageTemplate>) change) {
    final result = _tail.then((_) async => _write(change(await _read())));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  String _name(String name) =>
      name.trim().isEmpty ? 'Mi plantilla' : name.trim();
  void _validateBytes(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > 50 * 1024 * 1024) {
      throw const FormatException('La plantilla está vacía o supera los 50 MB');
    }
  }

  Future<PageTemplate> importImage(
    Uint8List bytes, {
    required String name,
  }) async {
    _validateBytes(bytes);
    final dimensions = await compute(_imageDimensions, bytes);
    final assetId = await assets.put(bytes);
    final template = PageTemplate(
      id: const Uuid().v4(),
      name: _name(name),
      width: dimensions.$1.toDouble(),
      height: dimensions.$2.toDouble(),
      background: PageBackground.image(assetId),
      coverAssetId: assetId,
    );
    await _mutate((own) => [...own, template]);
    return template;
  }

  /// A PDF contributes one reusable template for each original page. The first
  /// page is returned for immediate application; the picker exposes all pages.
  Future<PageTemplate> importPdf(
    Uint8List bytes, {
    required String name,
  }) async {
    _validateBytes(bytes);
    final note = await pdf.importDocument(
      bytes: bytes,
      title: _name(name),
      documentId: const Uuid().v4(),
      newId: const Uuid().v4,
      now: DateTime.now(),
    );
    final templates = <PageTemplate>[];
    for (var index = 0; index < note.pages.length; index++) {
      final page = note.pages[index];
      final preview = await pdf.renderBackground(
        page.background.assetId!,
        page.background.pageNumber!,
        scale: .5,
      );
      final cover = await assets.put(preview);
      templates.add(
        PageTemplate(
          id: const Uuid().v4(),
          name:
              '${_name(name)}${note.pages.length > 1 ? ' · ${index + 1}' : ''}',
          width: page.width,
          height: page.height,
          background: page.background,
          coverAssetId: cover,
        ),
      );
    }
    await _mutate((own) => [...own, ...templates]);
    return templates.first;
  }

  Future<void> remove(String id) =>
      _mutate((own) => own.where((t) => t.id != id).toList());
}

(int, int) _imageDimensions(Uint8List bytes) {
  try {
    final image.Decoder decoder;
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      decoder = image.PngDecoder();
    } else if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      decoder = image.JpegDecoder();
    } else {
      throw const FormatException('Usá una imagen PNG o JPEG');
    }
    final info = decoder.startDecode(bytes);
    if (info == null ||
        info.width < 1 ||
        info.height < 1 ||
        info.width * info.height > 40 * 1024 * 1024) {
      throw const FormatException(
        'La imagen no es válida o es demasiado grande',
      );
    }
    if (decoder.decodeFrame(0) == null) {
      throw const FormatException('No se pudo leer la imagen');
    }
    return (info.width, info.height);
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('La imagen está dañada');
  }
}
