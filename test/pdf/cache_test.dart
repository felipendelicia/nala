import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/pdf/background_cache.dart';

void main() {
  test(
    'el caché expulsa el menos usado contando también los píxeles decodificados',
    () {
      final released = <BackgroundKey>[];
      final cache = PdfBackgroundCache(
        maxBytes: 90,
        onEvict: (key, _) => released.add(key),
      );
      const a = (assetId: 'a', pageNumber: 1, scaleStep: 4);
      const b = (assetId: 'a', pageNumber: 2, scaleStep: 4);
      const c = (assetId: 'a', pageNumber: 3, scaleStep: 4);
      final bytes = Uint8List(10);
      cache.put(a, bytes, decodedBytes: 30);
      cache.put(b, bytes, decodedBytes: 30);
      expect(cache.get(a), same(bytes));
      cache.put(c, bytes, decodedBytes: 30);
      expect(cache.get(b), isNull);
      expect(cache.get(a), isNotNull);
      expect(released, [b]);
      cache.put(
        (assetId: 'large', pageNumber: 1, scaleStep: 4),
        Uint8List(100),
        decodedBytes: 0,
      );
      expect(cache.get(a), isNotNull);
      cache.clear();
      expect(cache.get(a), isNull);
      expect(cache.currentBytes, 0);
    },
  );
}
