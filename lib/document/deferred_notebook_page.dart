import 'dart:isolate';

import 'notebook.dart';
import 'notebook_codec.dart';
import 'page_comment.dart';
import 'page_object.dart';

/// The actual page from a stored revision, with its drawing data decoded
/// on demand. Layout can read its identity, bounds and background immediately.
class DeferredNotebookPage extends NotebookPage {
  DeferredNotebookPage({
    required super.id,
    required super.width,
    required super.height,
    required super.background,
    required this.encoded,
    NotebookPage? decoded,
  }) : _decoded = decoded {
    if (decoded != null) _checkMetadata(decoded);
  }

  final String encoded;
  NotebookPage? _decoded;

  // A Revision can be sent to the database isolate for saving while a page
  // is loading. Futures and their UI callbacks stay in their own isolate.
  static final _preparations = Expando<Future<void>>();

  bool get isReady => _decoded != null;

  bool reuseDecodedPage(DeferredNotebookPage other) {
    final decoded = other._decoded;
    if (decoded == null || encoded != other.encoded) return false;
    _decoded = _checkMetadata(decoded);
    return true;
  }

  NotebookPage materialize() =>
      _decoded ??= _checkMetadata(NotebookCodec.decodeEditingPage(encoded));

  Future<void> prepare() {
    if (isReady) return Future.value();
    return _preparations[this] ??= _decodeOffMainIsolate(encoded)
        .then<void>((page) {
          _decoded ??= _checkMetadata(page);
        })
        .whenComplete(() => _preparations[this] = null);
  }

  NotebookPage _checkMetadata(NotebookPage page) {
    if (page.id != id ||
        page.width != width ||
        page.height != height ||
        page.background.pattern != background.pattern ||
        page.background.assetId != background.assetId ||
        page.background.pageNumber != background.pageNumber) {
      throw const FormatException('Los datos de la hoja no coinciden.');
    }
    return page;
  }

  @override
  List<InkStroke> get strokes => materialize().strokes;

  @override
  List<PageComment> get comments => materialize().comments;

  @override
  List<PageObject> get objects => materialize().objects;

  @override
  String? get markdown => materialize().markdown;

  @override
  String get recognizedText => materialize().recognizedText;

  @override
  String? get recognitionFingerprint => materialize().recognitionFingerprint;

  @override
  Map<String, Object> toJson() => materialize().toJson();
}

Future<NotebookPage> _decodeOffMainIsolate(String encoded) =>
    Isolate.run(() => NotebookCodec.decodeEditingPage(encoded));
