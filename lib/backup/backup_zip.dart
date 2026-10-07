import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart' show getCrc32;

/// ZIP validation is deliberately independent of Archive's name coalescing and
/// lazy decompression. Check every directory entry before expanding any bytes.
Map<String, Uint8List> readBackupZip(Uint8List bytes) {
  const maxArchive = 128 * 1024 * 1024;
  const maxTotal = 256 * 1024 * 1024;
  const maxAsset = 64 * 1024 * 1024;
  const maxJson = 8 * 1024 * 1024;
  const maxFiles = 20000;
  if (bytes.length < 22 || bytes.length > maxArchive) {
    throw const FormatException('El backup está vacío o supera los 128 MB');
  }
  final data = ByteData.sublistView(bytes);
  int u16(int at) => data.getUint16(at, Endian.little);
  int u32(int at) => data.getUint32(at, Endian.little);
  var end = -1;
  for (
    var at = bytes.length - 22;
    at >= math.max(0, bytes.length - 22 - 65535);
    at--
  ) {
    if (u32(at) == 0x06054b50 && at + 22 + u16(at + 20) == bytes.length) {
      end = at;
      break;
    }
  }
  if (end < 0 ||
      u16(end + 4) != 0 ||
      u16(end + 6) != 0 ||
      u16(end + 8) != u16(end + 10)) {
    throw const FormatException('Archivo ZIP inválido');
  }
  final count = u16(end + 10);
  final directory = u32(end + 16);
  if (count < 2 || count > maxFiles || directory + u32(end + 12) != end) {
    throw const FormatException('Directorio ZIP inválido o demasiado grande');
  }
  final entries = <_Entry>[];
  final names = <String>{};
  var at = directory;
  var total = 0;
  for (var index = 0; index < count; index++) {
    if (at + 46 > end || u32(at) != 0x02014b50) {
      throw const FormatException('Directorio ZIP incompleto');
    }
    final flags = u16(at + 8), method = u16(at + 10);
    final compressed = u32(at + 20), size = u32(at + 24);
    final nameLength = u16(at + 28), extra = u16(at + 30);
    final comment = u16(at + 32), local = u32(at + 42);
    if (at + 46 + nameLength + extra + comment > end ||
        nameLength == 0 ||
        nameLength > 256 ||
        u16(at + 34) != 0 ||
        (flags & ~0x0808) != 0 ||
        (method != 0 && method != 8) ||
        ((u32(at + 38) >> 16) & 0xf000) == 0xa000) {
      throw const FormatException('Entrada ZIP no compatible');
    }
    final name = utf8.decode(bytes.sublist(at + 46, at + 46 + nameLength));
    if (!safeBackupPath(name) || !names.add(name)) {
      throw const FormatException('Ruta ZIP inválida o duplicada');
    }
    total += size;
    final limit = name.startsWith('assets/') ? maxAsset : maxJson;
    if ((method == 0 && compressed != size) ||
        size > limit ||
        total > maxTotal ||
        compressed > maxArchive ||
        local + 30 > directory ||
        u32(local) != 0x04034b50 ||
        u16(local + 6) != flags ||
        u16(local + 8) != method) {
      throw const FormatException('Archivo ZIP demasiado grande o dañado');
    }
    final localNameLength = u16(local + 26), localExtra = u16(local + 28);
    final start = local + 30 + localNameLength + localExtra;
    if (start + compressed > directory ||
        utf8.decode(bytes.sublist(local + 30, local + 30 + localNameLength)) !=
            name) {
      throw const FormatException('Cabecera ZIP inconsistente');
    }
    final crc = u32(at + 16);
    var finish = start + compressed;
    if ((flags & 8) == 0) {
      if (u32(local + 14) != crc ||
          u32(local + 18) != compressed ||
          u32(local + 22) != size) {
        throw const FormatException('Tamaño o CRC ZIP inconsistente');
      }
    } else {
      if (finish + 12 > directory) {
        throw const FormatException('Descriptor ZIP incompleto');
      }
      if (u32(finish) == 0x08074b50) finish += 4;
      if (finish + 12 > directory ||
          u32(finish) != crc ||
          u32(finish + 4) != compressed ||
          u32(finish + 8) != size) {
        throw const FormatException('Descriptor ZIP inconsistente');
      }
      finish += 12;
    }
    entries.add(
      _Entry(name, local, start, finish, compressed, size, method, crc),
    );
    at += 46 + nameLength + extra + comment;
  }
  if (at != end) throw const FormatException('Entradas ZIP sobrantes');
  final ordered = entries.toList()..sort((a, b) => a.local.compareTo(b.local));
  var previous = 0;
  for (final entry in ordered) {
    if (entry.local != previous) {
      throw const FormatException('Entradas ZIP superpuestas o sobrantes');
    }
    previous = entry.finish;
  }
  if (previous != directory) {
    throw const FormatException('Contenido ZIP sobrante');
  }
  final files = <String, Uint8List>{};
  for (final entry in entries) {
    final compressed = Uint8List.sublistView(
      bytes,
      entry.start,
      entry.start + entry.compressed,
    );
    final Uint8List content;
    if (entry.method == 0) {
      content = Uint8List.fromList(compressed);
    } else {
      final output = _BoundedSink(entry.size);
      final decoder = ZLibDecoder(raw: true).startChunkedConversion(output);
      for (var offset = 0; offset < compressed.length; offset += 1024) {
        decoder.add(
          Uint8List.sublistView(
            compressed,
            offset,
            math.min(offset + 1024, compressed.length),
          ),
        );
      }
      decoder.close();
      content = output.bytes.takeBytes();
    }
    if (content.length != entry.size || getCrc32(content) != entry.crc) {
      throw const FormatException('Tamaño o CRC ZIP incorrecto');
    }
    files[entry.name] = content;
  }
  return files;
}

bool safeBackupPath(String name) =>
    name == 'manifest.json' ||
    name == 'folders.json' ||
    RegExp(r'^revisions/[0-9]{6}\.json$').hasMatch(name) ||
    RegExp(r'^assets/[a-f0-9]{64}$').hasMatch(name) ||
    const {
      'config/templates/registry.json',
      'config/elements/registry.json',
      'config/pen-favorites.json',
      'config/pen.json',
      'config/toolbar.json',
      'config/appearance.json',
    }.contains(name);

class _Entry {
  const _Entry(
    this.name,
    this.local,
    this.start,
    this.finish,
    this.compressed,
    this.size,
    this.method,
    this.crc,
  );
  final String name;
  final int local, start, finish, compressed, size, method, crc;
}

class _BoundedSink implements Sink<List<int>> {
  _BoundedSink(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);
  int count = 0;
  @override
  void add(List<int> value) {
    count += value.length;
    if (count > limit) {
      throw const FormatException('Contenido ZIP supera su tamaño declarado');
    }
    bytes.add(value);
  }

  @override
  void close() {}
}
