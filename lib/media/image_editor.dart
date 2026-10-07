import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../document/asset_store.dart';
import '../document/notebook.dart' show finiteNumber;
import '../document/page_object.dart';

img.Image _decode(Uint8List bytes) {
  if (bytes.length > 25 * 1024 * 1024) {
    throw const FormatException('La imagen supera el límite de 25 MB.');
  }
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null ||
      (decoder is! img.PngDecoder && decoder is! img.JpegDecoder)) {
    throw const FormatException('Usá una imagen PNG o JPEG válida.');
  }
  final info = decoder.startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > 20 * 1024 * 1024) {
    throw const FormatException(
      'La imagen tiene demasiados píxeles o está dañada.',
    );
  }
  final image = decoder.decodeFrame(0);
  if (image == null) throw const FormatException('La imagen está dañada.');
  return img.bakeOrientation(image);
}

({int width, int height}) _dimensions(Uint8List bytes) {
  final image = _decode(bytes);
  return (width: image.width, height: image.height);
}

({Uint8List bytes, int beforeWidth, int beforeHeight, int width, int height})
_crop(({Uint8List bytes, Rect rect}) request) {
  final image = _decode(request.bytes);
  final rect = request.rect;
  final left = (rect.left * image.width).floor();
  final top = (rect.top * image.height).floor();
  final right = math.min(image.width, (rect.right * image.width).ceil());
  final bottom = math.min(image.height, (rect.bottom * image.height).ceil());
  final cropped = img.copyCrop(
    image,
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );
  return (
    bytes: img.encodePng(cropped),
    beforeWidth: image.width,
    beforeHeight: image.height,
    width: cropped.width,
    height: cropped.height,
  );
}

/// Crops the current image using normalized coordinates. Originals are never
/// rewritten. Reset retains the displayed pixel scale before any later crop.
Future<PageObject> editPageImage(
  AssetStore assets,
  PageObject object, {
  Rect? crop,
  bool reset = false,
  double? opacity,
}) async {
  if (object.kind != PageObjectKind.image) {
    throw const FormatException('Este objeto no es una imagen.');
  }
  if (opacity != null) finiteNumber(opacity, min: 0, max: 1);
  if (crop != null &&
      (!crop.left.isFinite ||
          !crop.top.isFinite ||
          !crop.width.isFinite ||
          !crop.height.isFinite ||
          crop.isEmpty ||
          crop.left < 0 ||
          crop.top < 0 ||
          crop.right > 1 ||
          crop.bottom > 1)) {
    throw const FormatException('El recorte debe estar dentro de la imagen.');
  }
  if (object.locked) return object;
  var result = object;
  if (reset && object.originalAssetId != null) {
    final current = await compute(
      _dimensions,
      await assets.read(object.assetId!),
    );
    final original = await compute(
      _dimensions,
      await assets.read(object.originalAssetId!),
    );
    result = object.copyWith(
      assetId: object.originalAssetId,
      originalAssetId: null,
      width: object.width * original.width / current.width,
      height: object.height * original.height / current.height,
    );
  }
  if (crop != null && crop != const Rect.fromLTWH(0, 0, 1, 1)) {
    final edited = await compute(_crop, (
      bytes: await assets.read(result.assetId!),
      rect: crop,
    ));
    result = result.copyWith(
      assetId: await assets.put(edited.bytes),
      originalAssetId: result.originalAssetId ?? result.assetId,
      width: result.width * edited.width / edited.beforeWidth,
      height: result.height * edited.height / edited.beforeHeight,
    );
  }
  return result.copyWith(opacity: opacity);
}

Future<PageObject?> showImageEditor(
  BuildContext context, {
  required AssetStore assets,
  required PageObject object,
}) {
  if (object.kind != PageObjectKind.image || object.locked) {
    return Future.value();
  }
  return showDialog<PageObject>(
    context: context,
    builder: (_) => _ImageEditor(assets: assets, object: object),
  );
}

class _ImageEditor extends StatefulWidget {
  const _ImageEditor({required this.assets, required this.object});
  final AssetStore assets;
  final PageObject object;
  @override
  State<_ImageEditor> createState() => _ImageEditorState();
}

class _ImageEditorState extends State<_ImageEditor> {
  late PageObject working;
  late double opacity;
  Uint8List? bytes;
  double aspect = 1;
  Rect crop = const Rect.fromLTWH(0, 0, 1, 1);
  Offset? start;
  String? error;
  bool busy = true;

  @override
  void initState() {
    super.initState();
    working = widget.object;
    opacity = working.opacity;
    load();
  }

  Future<void> load() async {
    try {
      final data = await widget.assets.read(working.assetId!);
      final dimensions = await compute(_dimensions, data);
      if (!mounted) return;
      setState(() {
        bytes = data;
        aspect = dimensions.width / dimensions.height;
        busy = false;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          error = 'No se pudo abrir la imagen: $e';
          busy = false;
        });
      }
    }
  }

  Future<void> save({bool reset = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await editPageImage(
        widget.assets,
        working,
        crop: reset ? null : crop,
        reset: reset,
        opacity: opacity,
      );
      if (!mounted) return;
      if (!reset) {
        Navigator.pop(context, result);
        return;
      }
      setState(() {
        working = result;
        crop = const Rect.fromLTWH(0, 0, 1, 1);
      });
      await load();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          error = 'No se pudo guardar la imagen: $e';
          busy = false;
        });
      }
    }
  }

  void select(Offset p, Size size, {bool begin = false}) {
    final normalized = Offset(
      (p.dx / size.width).clamp(0, 1),
      (p.dy / size.height).clamp(0, 1),
    );
    if (begin) start = normalized;
    final anchor = start;
    if (anchor == null) return;
    final next = Rect.fromPoints(anchor, normalized);
    if (next.width >= .005 && next.height >= .005) setState(() => crop = next);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Editar imagen'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Arrastrá sobre la imagen para elegir el recorte.'),
            const SizedBox(height: 12),
            if (bytes != null)
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = math.min(constraints.maxWidth, 280 * aspect);
                  final size = Size(width, width / aspect);
                  return Center(
                    child: SizedBox.fromSize(
                      size: size,
                      child: GestureDetector(
                        onPanStart: busy
                            ? null
                            : (d) => select(d.localPosition, size, begin: true),
                        onPanUpdate: busy
                            ? null
                            : (d) => select(d.localPosition, size),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(
                              color: const Color(0xffe8e8e8),
                              child: Opacity(
                                opacity: opacity,
                                child: Image.memory(bytes!, fit: BoxFit.fill),
                              ),
                            ),
                            CustomPaint(painter: _CropPainter(crop)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            Text('Opacidad: ${(opacity * 100).round()} %'),
            Slider(
              value: opacity,
              onChanged: busy ? null : (v) => setState(() => opacity = v),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(
                          () => crop = const Rect.fromLTWH(0, 0, 1, 1),
                        ),
                  icon: const Icon(Icons.crop_free),
                  label: const Text('Quitar selección'),
                ),
                if (working.originalAssetId != null)
                  TextButton.icon(
                    onPressed: busy ? null : () => save(reset: true),
                    icon: const Icon(Icons.restore),
                    label: const Text('Restablecer original'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: busy || bytes == null ? null : save,
        child: const Text('Guardar'),
      ),
    ],
  );
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.crop);
  final Rect crop;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      crop.left * size.width,
      crop.top * size.height,
      crop.width * size.width,
      crop.height * size.height,
    );
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(shade, Paint()..color = const Color(0x77000000));
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => crop != oldDelegate.crop;
}
