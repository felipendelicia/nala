import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;
import '../document/asset_store.dart';

typedef PreparedPageImage = ({Uint8List bytes, int width, int height});

PreparedPageImage preparePageImage(Uint8List bytes) {
  if (bytes.length > 25 * 1024 * 1024) {
    throw const FormatException(
      'La imagen es demasiado grande (máximo 25 MB).',
    );
  }
  img.Decoder? decoder;
  try {
    if (bytes.length >= 8 && img.PngDecoder().isValidFile(bytes)) {
      decoder = img.PngDecoder();
    } else if (bytes.length >= 4 && img.JpegDecoder().isValidFile(bytes)) {
      decoder = img.JpegDecoder();
    } else {
      throw const FormatException('Usá una imagen PNG o JPEG válida.');
    }
  } on Object {
    throw const FormatException('Usá una imagen PNG o JPEG válida.');
  }
  final info = decoder.startDecode(bytes);
  if (info == null || info.width <= 0 || info.height <= 0) {
    throw const FormatException('No se pudo abrir esta imagen.');
  }
  if (info.width * info.height > 20 * 1024 * 1024) {
    throw const FormatException(
      'La imagen tiene demasiados píxeles. Usá una copia más pequeña.',
    );
  }
  var image = decoder.decodeFrame(0);
  if (image == null) throw const FormatException('La imagen está dañada.');
  image = img.bakeOrientation(image);
  if (image.width > 2048 || image.height > 2048) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 2048 : null,
      height: image.height > image.width ? 2048 : null,
      interpolation: img.Interpolation.average,
    );
  }
  return (
    bytes: img.encodePng(image),
    width: image.width,
    height: image.height,
  );
}

Future<({String assetId, int width, int height})?> importPageImage(
  AssetStore assets,
) async {
  final file = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(
        label: 'Imágenes',
        extensions: ['png', 'jpg', 'jpeg'],
        mimeTypes: ['image/png', 'image/jpeg'],
      ),
    ],
  );
  if (file == null) return null;
  if (await file.length() > 25 * 1024 * 1024) {
    throw const FormatException(
      'La imagen es demasiado grande (máximo 25 MB).',
    );
  }
  final image = await compute(preparePageImage, await file.readAsBytes());
  return (
    assetId: await assets.put(image.bytes),
    width: image.width,
    height: image.height,
  );
}
