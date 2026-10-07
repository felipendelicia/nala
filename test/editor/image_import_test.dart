import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:apuntes/media/image_import.dart';

void main() {
  test('image import normalizes supported media and retains aspect ratio', () {
    final source = img.Image(width: 2400, height: 1200);
    final result = preparePageImage(img.encodePng(source));
    expect(result.width, 2048);
    expect(result.height, 1024);
    expect(img.decodePng(result.bytes)!.width, 2048);
  });
  test('image import rejects corrupt data', () {
    expect(
      () => preparePageImage(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
