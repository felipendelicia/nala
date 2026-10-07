import 'notebook.dart' show finiteNumber, nonEmpty, validAssetId;
import 'page_link.dart';

enum PageObjectKind { text, image, latex }

/// A positioned page object. Rotation is measured in radians about its center.
class PageObject {
  PageObject({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.text = '',
    this.argb = 0xff202020,
    this.fontSize = 16,
    this.assetId,
    this.originalAssetId,
    this.opacity = 1,
    this.locked = false,
    this.link,
  }) {
    nonEmpty(id);
    finiteNumber(x);
    finiteNumber(y);
    finiteNumber(width, positive: true);
    finiteNumber(height, positive: true);
    finiteNumber(rotation);
    finiteNumber(fontSize, positive: true);
    finiteNumber(opacity, min: 0, max: 1);
    if (originalAssetId != null) {
      validAssetId(originalAssetId);
      if (kind != PageObjectKind.image) {
        throw const FormatException('El original requiere una imagen');
      }
    }
    if (argb < 0 || argb > 0xffffffff) {
      throw const FormatException('Color de objeto inválido');
    }
    switch (kind) {
      case PageObjectKind.text:
        if (text.trim().isEmpty || assetId != null) {
          throw const FormatException('Objeto de texto inválido');
        }
      case PageObjectKind.image:
        validAssetId(assetId);
        if (text.isNotEmpty) {
          throw const FormatException('Objeto de imagen inválido');
        }
      case PageObjectKind.latex:
        validAssetId(assetId);
        if (text.trim().isEmpty || text.length > 4000) {
          throw const FormatException('Fórmula inválida');
        }
    }
  }

  final String id;
  final PageObjectKind kind;
  final double x, y, width, height, rotation;
  final String text;
  final int argb;
  final double fontSize;
  final String? assetId;
  final String? originalAssetId;
  final double opacity;
  final bool locked;
  final PageLink? link;

  PageObject copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    String? text,
    int? argb,
    double? fontSize,
    Object? assetId = _keepReference,
    Object? originalAssetId = _keepReference,
    double? opacity,
    bool? locked,
    Object? link = _keepReference,
  }) => PageObject(
    id: id ?? this.id,
    kind: kind,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    rotation: rotation ?? this.rotation,
    text: text ?? this.text,
    argb: argb ?? this.argb,
    fontSize: fontSize ?? this.fontSize,
    assetId: identical(assetId, _keepReference)
        ? this.assetId
        : assetId as String?,
    originalAssetId: identical(originalAssetId, _keepReference)
        ? this.originalAssetId
        : originalAssetId as String?,
    opacity: opacity ?? this.opacity,
    locked: locked ?? this.locked,
    link: identical(link, _keepReference) ? this.link : link as PageLink?,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind.name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    if (rotation != 0) 'rotation': rotation,
    if (kind != PageObjectKind.image) 'text': text,
    if (argb != 0xff202020) 'argb': argb,
    if (fontSize != 16) 'fontSize': fontSize,
    'assetId': ?assetId,
    'originalAssetId': ?originalAssetId,
    if (opacity != 1) 'opacity': opacity,
    if (locked) 'locked': true,
    if (link != null) 'link': link!.toJson(),
  };

  factory PageObject.fromJson(Map<String, dynamic> json) => PageObject(
    id: nonEmpty(json['id']),
    kind: PageObjectKind.values.byName(json['kind'] as String),
    x: finiteNumber(json['x']),
    y: finiteNumber(json['y']),
    width: finiteNumber(json['width'], positive: true),
    height: finiteNumber(json['height'], positive: true),
    rotation: finiteNumber(json['rotation'] ?? 0),
    text: json['text'] as String? ?? '',
    argb: json['argb'] as int? ?? 0xff202020,
    fontSize: finiteNumber(json['fontSize'] ?? 16, positive: true),
    assetId: json['assetId'] as String?,
    originalAssetId: json['originalAssetId'] as String?,
    opacity: finiteNumber(json['opacity'] ?? 1, min: 0, max: 1),
    locked: json['locked'] as bool? ?? false,
    link: json['link'] == null
        ? null
        : PageLink.fromJson(json['link'] as Map<String, dynamic>),
  );
}

const _keepReference = Object();
