import 'page_comment.dart';
import 'page_object.dart';
import 'notebook_recording.dart';
import '../study/study_card.dart';

enum PaperPattern { blank, ruled, grid, dots, cornell, weekly }

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
    this.audioRecordingId,
    this.audioOffsetMs,
  }) : points = List.unmodifiable(points) {
    if ((audioRecordingId == null) != (audioOffsetMs == null) ||
        (audioOffsetMs != null && audioOffsetMs! < 0)) {
      throw const FormatException('Referencia de grabación inválida');
    }
    if (audioRecordingId != null) nonEmpty(audioRecordingId);
  }
  final String id;
  final InkTool tool;
  final int argb;
  final double width;
  final PressureCurve pressureCurve;
  final double sensitivity;
  final List<InkPoint> points;
  final String? audioRecordingId;
  final int? audioOffsetMs;
  InkStroke copyWith({
    String? id,
    int? argb,
    double? width,
    List<InkPoint>? points,
    Object? audioRecordingId = _keepAudioMetadata,
    Object? audioOffsetMs = _keepAudioMetadata,
  }) => InkStroke(
    id: id ?? this.id,
    tool: tool,
    argb: argb ?? this.argb,
    width: width ?? this.width,
    points: points ?? this.points,
    pressureCurve: pressureCurve,
    sensitivity: sensitivity,
    audioRecordingId: identical(audioRecordingId, _keepAudioMetadata)
        ? this.audioRecordingId
        : audioRecordingId as String?,
    audioOffsetMs: identical(audioOffsetMs, _keepAudioMetadata)
        ? this.audioOffsetMs
        : audioOffsetMs as int?,
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
    'audioRecordingId': ?audioRecordingId,
    'audioOffsetMs': ?audioOffsetMs,
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
      audioRecordingId: json['audioRecordingId'] as String?,
      audioOffsetMs: json['audioOffsetMs'] as int?,
    );
  }
}

const _keepAudioMetadata = Object();

class PageBackground {
  const PageBackground.paper(PaperPattern this.pattern)
    : assetId = null,
      pageNumber = null;
  const PageBackground.pdf(String this.assetId, int this.pageNumber)
    : pattern = null;
  const PageBackground.image(String this.assetId)
    : pattern = null,
      pageNumber = null;
  final PaperPattern? pattern;
  final String? assetId;
  final int? pageNumber;
  bool get isImage => assetId != null && pageNumber == null;
  bool get isPdf => assetId != null && pageNumber != null;
  String get kind => pattern != null
      ? 'paper'
      : isPdf
      ? 'pdf'
      : 'image';
  Map<String, Object> toJson() => pattern != null
      ? {'kind': 'paper', 'pattern': pattern!.name}
      : {'kind': kind, 'assetId': assetId!, 'pageNumber': ?pageNumber};
  factory PageBackground.fromJson(Map<String, dynamic> json) {
    if (json['kind'] == 'paper' &&
        !json.containsKey('assetId') &&
        !json.containsKey('pageNumber')) {
      return PageBackground.paper(
        PaperPattern.values.byName(json['pattern'] as String),
      );
    }
    if (json['kind'] == 'pdf' && !json.containsKey('pattern')) {
      final asset = validAssetId(json['assetId']);
      final number = json['pageNumber'];
      if (number is! int || number < 1) {
        throw const FormatException('Fondo PDF inválido');
      }
      return PageBackground.pdf(asset, number);
    }
    if (json['kind'] == 'image' &&
        !json.containsKey('pattern') &&
        !json.containsKey('pageNumber')) {
      return PageBackground.image(validAssetId(json['assetId']));
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
    List<PageComment> comments = const [],
    List<PageObject> objects = const [],
    this.recognizedText = '',
    this.recognitionFingerprint,
  }) : strokes = List.unmodifiable(strokes),
       comments = List.unmodifiable(comments),
       objects = List.unmodifiable(objects) {
    if (recognitionFingerprint != null) validAssetId(recognitionFingerprint);
  }
  final String id;
  final double width, height;
  final PageBackground background;
  final List<InkStroke> strokes;
  final List<PageComment> comments;
  final List<PageObject> objects;
  final String recognizedText;
  final String? recognitionFingerprint;
  NotebookPage copyWith({
    PageBackground? background,
    List<InkStroke>? strokes,
    List<PageComment>? comments,
    List<PageObject>? objects,
    double? width,
    double? height,
    String? recognizedText,
    Object? recognitionFingerprint = _keepRecognition,
  }) => NotebookPage(
    id: id,
    width: width ?? this.width,
    height: height ?? this.height,
    background: background ?? this.background,
    strokes: strokes ?? this.strokes,
    comments: comments ?? this.comments,
    objects: objects ?? this.objects,
    recognizedText: recognizedText ?? this.recognizedText,
    recognitionFingerprint: identical(recognitionFingerprint, _keepRecognition)
        ? this.recognitionFingerprint
        : recognitionFingerprint as String?,
  );
  Map<String, Object> toJson() => {
    'id': id,
    'width': width,
    'height': height,
    'background': background.toJson(),
    'strokes': strokes.map((s) => s.toJson()).toList(),
    if (comments.isNotEmpty)
      'comments': comments.map((c) => c.toJson()).toList(),
    if (objects.isNotEmpty) 'objects': objects.map((o) => o.toJson()).toList(),
    if (recognizedText.isNotEmpty) 'recognizedText': recognizedText,
    'recognitionFingerprint': ?recognitionFingerprint,
  };
  factory NotebookPage.fromJson(Map<String, dynamic> json) => NotebookPage(
    recognizedText: json['recognizedText'] as String? ?? '',
    recognitionFingerprint: json['recognitionFingerprint'] == null
        ? null
        : validAssetId(json['recognitionFingerprint']),
    objects: (json['objects'] as List? ?? [])
        .map((o) => PageObject.fromJson(o as Map<String, dynamic>))
        .toList(),
    comments: (json['comments'] as List? ?? [])
        .map((c) => PageComment.fromJson(c as Map<String, dynamic>))
        .toList(),
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

const _keepRecognition = Object();

const _keepFolder = Object();

class Notebook {
  Notebook({
    required this.id,
    required this.title,
    required this.subject,
    this.folderId,
    required List<NotebookPage> pages,
    required this.updatedAt,
    List<NotebookRecording> recordings = const [],
    List<StudyCard> studyCards = const [],
    this.coverAssetId,
  }) : pages = List.unmodifiable(pages),
       recordings = List.unmodifiable(recordings),
       studyCards = List.unmodifiable(studyCards) {
    if (coverAssetId != null) validAssetId(coverAssetId);
  }
  final String id, title, subject;
  final String? folderId;
  final List<NotebookPage> pages;
  final DateTime updatedAt;
  final List<NotebookRecording> recordings;
  final List<StudyCard> studyCards;
  final String? coverAssetId;
  factory Notebook.blank({
    required String id,
    required String pageId,
    required String title,
    String subject = '',
    String? folderId,
    required PaperPattern pattern,
    required DateTime now,
  }) => Notebook(
    id: id,
    title: title,
    subject: subject,
    folderId: folderId,
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
    Object? folderId = _keepFolder,
    List<NotebookPage>? pages,
    DateTime? updatedAt,
    List<NotebookRecording>? recordings,
    List<StudyCard>? studyCards,
    Object? coverAssetId = _keepCover,
  }) => Notebook(
    id: id,
    title: title ?? this.title,
    subject: subject ?? this.subject,
    folderId: identical(folderId, _keepFolder)
        ? this.folderId
        : folderId as String?,
    pages: pages ?? this.pages,
    updatedAt: updatedAt ?? this.updatedAt,
    recordings: recordings ?? this.recordings,
    studyCards: studyCards ?? this.studyCards,
    coverAssetId: identical(coverAssetId, _keepCover)
        ? this.coverAssetId
        : coverAssetId as String?,
  );
}

const _keepCover = Object();

String validAssetId(Object? value) {
  final id = nonEmpty(value);
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
    throw const FormatException('Identificador de recurso inválido');
  }
  return id;
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
