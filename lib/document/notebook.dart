enum PaperPattern { blank, ruled, grid, dots }

enum InkTool { pen, highlighter }

enum PressureCurve { legacy, expressive, uniform }

enum EditorTool { pen, highlighter, eraser, selection }

class InkPoint {
  const InkPoint({required this.x, required this.y, required this.pressure});
  final double x, y, pressure;
  Map<String, Object> toJson() => {'x': x, 'y': y, 'pressure': pressure};
  factory InkPoint.fromJson(Map<String, dynamic> json) => InkPoint(
    x: finiteNumber(json['x']),
    y: finiteNumber(json['y']),
    pressure: finiteNumber(json['pressure'], min: 0, max: 1),
  );
}

class InkStroke {
  InkStroke({
    required this.id,
    required this.tool,
    required this.argb,
    required this.width,
    required List<InkPoint> points,
    this.pressureCurve = PressureCurve.legacy,
    this.sensitivity = 1,
  }) : points = List.unmodifiable(points);
  final String id;
  final InkTool tool;
  final int argb;
  final double width;
  final PressureCurve pressureCurve;
  final double sensitivity;
  final List<InkPoint> points;
  InkStroke copyWith({List<InkPoint>? points}) => InkStroke(
    id: id,
    tool: tool,
    argb: argb,
    width: width,
    points: points ?? this.points,
    pressureCurve: pressureCurve,
    sensitivity: sensitivity,
  );
  Map<String, Object> toJson() => {
    'id': id,
    'tool': tool.name,
    'argb': argb,
    'width': width,
    'points': points.map((p) => p.toJson()).toList(),
    if (pressureCurve != PressureCurve.legacy)
      'pressureCurve': pressureCurve.name,
    if (sensitivity != 1) 'sensitivity': sensitivity,
  };
  factory InkStroke.fromJson(Map<String, dynamic> json) {
    final points = (json['points'] as List)
        .map((p) => InkPoint.fromJson(p as Map<String, dynamic>))
        .toList();
    if (points.isEmpty) throw const FormatException('Trazo vacío');
    final color = json['argb'];
    if (color is! int || color < 0 || color > 0xffffffff) {
      throw const FormatException('Color inválido');
    }
    return InkStroke(
      id: nonEmpty(json['id']),
      tool: InkTool.values.byName(json['tool'] as String),
      argb: color,
      width: finiteNumber(json['width'], positive: true),
      points: points,
      pressureCurve: json['pressureCurve'] == null
          ? PressureCurve.legacy
          : PressureCurve.values.byName(json['pressureCurve'] as String),
      sensitivity: finiteNumber(json['sensitivity'] ?? 1, min: 0, max: 1),
    );
  }
}

class PageBackground {
  const PageBackground.paper(PaperPattern this.pattern)
    : assetId = null,
      pageNumber = null;
  const PageBackground.pdf(String this.assetId, int this.pageNumber)
    : pattern = null;
  final PaperPattern? pattern;
  final String? assetId;
  final int? pageNumber;
  Map<String, Object> toJson() => pattern != null
      ? {'kind': 'paper', 'pattern': pattern!.name}
      : {'kind': 'pdf', 'assetId': assetId!, 'pageNumber': pageNumber!};
  factory PageBackground.fromJson(Map<String, dynamic> json) {
    if (json['kind'] == 'paper' &&
        !json.containsKey('assetId') &&
        !json.containsKey('pageNumber')) {
      return PageBackground.paper(
        PaperPattern.values.byName(json['pattern'] as String),
      );
    }
    if (json['kind'] == 'pdf' && !json.containsKey('pattern')) {
      final asset = nonEmpty(json['assetId']);
      final number = json['pageNumber'];
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(asset) ||
          number is! int ||
          number < 1) {
        throw const FormatException('Fondo PDF inválido');
      }
      return PageBackground.pdf(asset, number);
    }
    throw const FormatException('Fondo de hoja inválido');
  }
}

class NotebookPage {
  NotebookPage({
    required this.id,
    required this.width,
    required this.height,
    required this.background,
    List<InkStroke> strokes = const [],
  }) : strokes = List.unmodifiable(strokes);
  final String id;
  final double width, height;
  final PageBackground background;
  final List<InkStroke> strokes;
  NotebookPage copyWith({
    PageBackground? background,
    List<InkStroke>? strokes,
  }) => NotebookPage(
    id: id,
    width: width,
    height: height,
    background: background ?? this.background,
    strokes: strokes ?? this.strokes,
  );
  Map<String, Object> toJson() => {
    'id': id,
    'width': width,
    'height': height,
    'background': background.toJson(),
    'strokes': strokes.map((s) => s.toJson()).toList(),
  };
  factory NotebookPage.fromJson(Map<String, dynamic> json) => NotebookPage(
    id: nonEmpty(json['id']),
    width: finiteNumber(json['width'], positive: true),
    height: finiteNumber(json['height'], positive: true),
    background: PageBackground.fromJson(
      json['background'] as Map<String, dynamic>,
    ),
    strokes: (json['strokes'] as List)
        .map((s) => InkStroke.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
}

class Notebook {
  Notebook({
    required this.id,
    required this.title,
    required this.subject,
    required List<NotebookPage> pages,
    required this.updatedAt,
  }) : pages = List.unmodifiable(pages);
  final String id, title, subject;
  final List<NotebookPage> pages;
  final DateTime updatedAt;
  factory Notebook.blank({
    required String id,
    required String pageId,
    required String title,
    String subject = '',
    required PaperPattern pattern,
    required DateTime now,
  }) => Notebook(
    id: id,
    title: title,
    subject: subject,
    updatedAt: now,
    pages: [
      NotebookPage(
        id: pageId,
        width: 595.28,
        height: 841.89,
        background: PageBackground.paper(pattern),
      ),
    ],
  );
  Notebook copyWith({
    String? title,
    String? subject,
    List<NotebookPage>? pages,
    DateTime? updatedAt,
  }) => Notebook(
    id: id,
    title: title ?? this.title,
    subject: subject ?? this.subject,
    pages: pages ?? this.pages,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

String nonEmpty(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Identificador vacío');
  }
  return value;
}

double finiteNumber(
  Object? value, {
  bool positive = false,
  double? min,
  double? max,
}) {
  if (value is! num ||
      !value.isFinite ||
      (positive && value <= 0) ||
      (min != null && value < min) ||
      (max != null && value > max)) {
    throw const FormatException('Número inválido');
  }
  return value.toDouble();
}
