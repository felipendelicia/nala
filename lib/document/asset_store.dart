import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

abstract interface class AssetStore {
  Future<String> put(Uint8List bytes);
  Future<Uint8List> read(String assetId);
  Future<bool> contains(String assetId);
}

Future<String> assetFileHash(File file) {
  final path = file.path;
  return Isolate.run(() async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  });
}

class FileAssetStore implements AssetStore {
  FileAssetStore(this.directory);
  final String directory;
  File _file(String id) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
      throw const FormatException('Recurso inválido');
    }
    return File(p.join(directory, id));
  }

  @override
  Future<String> put(Uint8List bytes) async {
    final id = await Isolate.run(() => sha256.convert(bytes).toString());
    await _writeAtomically(id, (temporary) async {
      await temporary.writeAsBytes(bytes, flush: true);
    });
    return id;
  }

  Future<File> verifiedFile(String assetId) async {
    final file = _file(assetId);
    if (await assetFileHash(file) != assetId) {
      throw const FormatException('Recurso dañado');
    }
    return file;
  }

  Future<void> putVerifiedFile(String assetId, File source) =>
      _writeAtomically(assetId, (temporary) async {
        final destination = await temporary.open(mode: FileMode.write);
        try {
          await for (final block in source.openRead()) {
            await destination.writeFrom(block);
          }
          await destination.flush();
        } finally {
          await destination.close();
        }
      });

  Future<void> _writeAtomically(
    String id,
    Future<void> Function(File temporary) write,
  ) async {
    final destination = _file(id);
    await destination.parent.create(recursive: true);
    final temporary = File(p.join(directory, '${const Uuid().v4()}.tmp'));
    try {
      await write(temporary);
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<Uint8List> read(String assetId) async {
    final bytes = await _file(assetId).readAsBytes();
    final hash = await Isolate.run(() => sha256.convert(bytes).toString());
    if (hash != assetId) throw const FormatException('Recurso dañado');
    return bytes;
  }

  @override
  Future<bool> contains(String assetId) => _file(assetId).exists();
}
