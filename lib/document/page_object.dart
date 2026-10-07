import 'notebook.dart' show finiteNumber, nonEmpty, validAssetId;

enum PageObjectKind { text, image }

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
  }) {
    nonEmpty(id);
    finiteNumber(x);
    finiteNumber(y);
    finiteNumber(width, positive: true);
    finiteNumber(height, positive: true);
    finiteNumber(rotation);
    finiteNumber(fontSize, positive: true);
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
    }
  }

  final String id;
  final PageObjectKind kind;
  final double x, y, width, height, rotation;
  final String text;
  final int argb;
  final double fontSize;
  final String? assetId;

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
    assetId: assetId,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind.name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    if (rotation != 0) 'rotation': rotation,
    if (kind == PageObjectKind.text) 'text': text,
    if (argb != 0xff202020) 'argb': argb,
    if (fontSize != 16) 'fontSize': fontSize,
    'assetId': ?assetId,
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
  );
}
