import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart' show pdfrxFlutterInitialize;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import '../document/asset_store.dart';
import '../document/notebook.dart';
import 'background_cache.dart';

class PdfRenderCancelled implements Exception {}

class PdfRenderCancellation {
  bool isCancelled = false;
  void Function()? _onCancel;
  void cancel() {
    isCancelled = true;
    _onCancel?.call();
  }

  void _check() {
    if (isCancelled) throw PdfRenderCancelled();
  }
}

typedef PdfPixels = ({Uint8List pixels, int width, int height});
Uint8List encodePdfPixels(PdfPixels frame) => img.encodePng(
  img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: frame.pixels.buffer,
    bytesOffset: frame.pixels.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.bgra,
  ),
);

class PdfService {
  PdfService({required this.assets, Future<void> Function()? initialize})
    : _initialize = initialize ?? pdfrxFlutterInitialize,
      cache = PdfBackgroundCache(
        onEvict: (_, bytes) {
          MemoryImage(bytes).evict();
        },
      );
  final AssetStore assets;
  final Future<void> Function() _initialize;
  final PdfBackgroundCache cache;
  final Map<String, String> _passwords = {};
  final Set<PdfRenderCancellation> _active = {};
  Future<void>? _initialization;
  Future<void> _renderTail = Future.value();
  bool _disposed = false;
  Future<void> initialize() async {
    if (_disposed) throw StateError('Servicio cerrado');
    await (_initialization ??= _initialize());
  }

  Map<String, String> get sessionPasswords => Map.unmodifiable(_passwords);

  Future<Notebook> importDocument({
    required Uint8List bytes,
    required String title,
    required String documentId,
    required String Function() newId,
    required DateTime now,
    String? password,
  }) async {
    await initialize();
    final document = await PdfDocument.openData(
      bytes,
      passwordProvider: createSimplePasswordProvider(password),
    );
    try {
      if (document.pages.isEmpty ||
          document.pages.any(
            (p) =>
                !p.width.isFinite ||
                !p.height.isFinite ||
                p.width <= 0 ||
                p.height <= 0,
          )) {
        throw const FormatException('El PDF no contiene páginas válidas');
      }
      final assetId = await assets.put(bytes);
      if (password != null) _passwords[assetId] = password;
      return Notebook(
        id: documentId,
        title: title.trim().isEmpty ? 'PDF sin título' : title.trim(),
        subject: '',
        updatedAt: now.toUtc(),
        pages: [
          for (final page in document.pages)
            NotebookPage(
              id: newId(),
              width: page.width,
              height: page.height,
              background: PageBackground.pdf(assetId, page.pageNumber),
              strokes: const [],
            ),
        ],
      );
    } finally {
      await document.dispose();
    }
  }

  Future<void> unlock(String assetId, String password) async {
    await initialize();
    final document = await PdfDocument.openData(
      await assets.read(assetId),
      passwordProvider: createSimplePasswordProvider(password),
    );
    try {
      _passwords[assetId] = password;
    } finally {
      await document.dispose();
    }
  }

  static int scaleStep(double scale) {
    if (!scale.isFinite || scale <= 0) {
      throw ArgumentError.value(scale, 'scale');
    }
    return (scale * 4).ceil().clamp(1, 16);
  }

  Uint8List? cachedBackground(
    String assetId,
    int pageNumber, {
    double scale = 1,
  }) => cache.get((
    assetId: assetId,
    pageNumber: pageNumber,
    scaleStep: scaleStep(scale),
  ));

  Future<Uint8List> renderBackground(
    String assetId,
    int pageNumber, {
    required double scale,
    PdfRenderCancellation? cancellation,
  }) async {
    final token = cancellation ?? PdfRenderCancellation();
    token._check();
    final key = (
      assetId: assetId,
      pageNumber: pageNumber,
      scaleStep: scaleStep(scale),
    );
    final cached = cache.get(key);
    if (cached != null) return cached;
    _active.add(token);
    final result = _renderTail.then((_) => _render(key, token));
    _renderTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    try {
      return await result;
    } finally {
      _active.remove(token);
    }
  }

  Future<Uint8List> _render(
    BackgroundKey key,
    PdfRenderCancellation token,
  ) async {
    token._check();
    await initialize();
    final cached = cache.get(key);
    if (cached != null) return cached;
    final document = await PdfDocument.openData(
      await assets.read(key.assetId),
      passwordProvider: createSimplePasswordProvider(_passwords[key.assetId]),
    );
    try {
      token._check();
      if (key.pageNumber < 1 || key.pageNumber > document.pages.length) {
        throw RangeError('Página fuera del PDF');
      }
      final page = document.pages[key.pageNumber - 1];
      final scale = min(
        key.scaleStep / 4,
        sqrt(8 * 1024 * 1024 / (page.width * page.height)),
      );
      final width = (page.width * scale).ceil(),
          height = (page.height * scale).ceil();
      final nativeToken = page.createCancellationToken();
      token._onCancel = nativeToken.cancel;
      final rendered = await page.render(
        width: width,
        height: height,
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),
        backgroundColor: 0xffffffff,
        cancellationToken: nativeToken,
      );
      if (rendered == null) throw PdfRenderCancelled();
      PdfPixels frame;
      try {
        frame = (
          pixels: Uint8List.fromList(rendered.pixels),
          width: rendered.width,
          height: rendered.height,
        );
      } finally {
        rendered.dispose();
      }
      token._check();
      final png = await compute(encodePdfPixels, frame);
      token._check();
      cache.put(key, png, decodedBytes: width * height * 4);
      return png;
    } finally {
      token._onCancel = null;
      await document.dispose();
    }
  }

  /// Uses the same queue and native document lifecycle as background rendering.
  /// A cancelled search discards its result; every opened document is disposed.
  Future<String> extractText(
    String assetId,
    int pageNumber, {
    PdfRenderCancellation? cancellation,
  }) async {
    final token = cancellation ?? PdfRenderCancellation();
    token._check();
    _active.add(token);
    final result = _renderTail.then((_) async {
      token._check();
      await initialize();
      final document = await PdfDocument.openData(
        await assets.read(assetId),
        passwordProvider: createSimplePasswordProvider(_passwords[assetId]),
      );
      try {
        token._check();
        if (pageNumber < 1 || pageNumber > document.pages.length) {
          throw RangeError('Página fuera del PDF');
        }
        final text = await document.pages[pageNumber - 1].loadText();
        token._check();
        return text?.fullText ?? '';
      } finally {
        await document.dispose();
      }
    });
    _renderTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    try {
      return await result;
    } finally {
      _active.remove(token);
    }
  }

  void dispose() {
    _disposed = true;
    for (final token in _active) {
      token.cancel();
    }
    _passwords.clear();
    cache.clear();
  }
}
