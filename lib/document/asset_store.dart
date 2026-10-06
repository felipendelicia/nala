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

class FileAssetStore implements AssetStore {
  FileAssetStore(this.directory);
  final String directory;
  File _file(String id) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id))
      throw const FormatException('Recurso inválido');
    return File(p.join(directory, id));
  }

  @override
  Future<String> put(Uint8List bytes) async {
    final id = await Isolate.run(() => sha256.convert(bytes).toString());
    await Directory(directory).create(recursive: true);
    final temporary = File(p.join(directory, '${const Uuid().v4()}.tmp'));
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(_file(id).path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return id;
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
