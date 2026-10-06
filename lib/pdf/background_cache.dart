import 'dart:typed_data';

typedef BackgroundKey = ({String assetId, int pageNumber, int scaleStep});

class PdfBackgroundCache {
  PdfBackgroundCache({this.maxBytes = 64 * 1024 * 1024, this.onEvict});
  final int maxBytes;
  final void Function(BackgroundKey, Uint8List)? onEvict;
  final _entries = <BackgroundKey, ({Uint8List bytes, int cost})>{};
  int currentBytes = 0;
  Uint8List? latestFor(String assetId, int pageNumber) {
    for (final key in _entries.keys.toList().reversed) {
      if (key.assetId == assetId && key.pageNumber == pageNumber) {
        return get(key);
      }
    }
    return null;
  }

  Uint8List? get(BackgroundKey key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    return entry.bytes;
  }

  void put(BackgroundKey key, Uint8List bytes, {required int decodedBytes}) {
    final cost = bytes.length + decodedBytes;
    if (cost > maxBytes) return;
    _remove(key);
    while (currentBytes + cost > maxBytes && _entries.isNotEmpty) {
      _remove(_entries.keys.first);
    }
    _entries[key] = (bytes: bytes, cost: cost);
    currentBytes += cost;
  }

  void _remove(BackgroundKey key) {
    final entry = _entries.remove(key);
    if (entry == null) return;
    currentBytes -= entry.cost;
    onEvict?.call(key, entry.bytes);
  }

  void clear() {
    for (final key in _entries.keys.toList()) {
      _remove(key);
    }
  }
}
