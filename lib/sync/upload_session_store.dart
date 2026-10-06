import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

abstract interface class UploadSessionStore {
  Future<Uri?> read(String accountId, String assetId);
  Future<void> write(String accountId, String assetId, Uri url);
  Future<void> delete(String accountId, String assetId);
}

class FileUploadSessionStore implements UploadSessionStore {
  FileUploadSessionStore(this.directory);
  final String directory;
  File _file(String assetId) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(assetId)) {
      throw const FormatException('Recurso inválido');
    }
    return File('$directory/$assetId.json');
  }

  @override
  Future<Uri?> read(String accountId, String assetId) async {
    final file = _file(assetId);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['accountId'] is! String ||
          decoded['url'] is! String) {
        throw const FormatException('Sesión inválida');
      }
      final json = decoded;
      return json['accountId'] == accountId
          ? Uri.parse(json['url'] as String)
          : null;
    } on FormatException {
      await file.delete();
      return null;
    }
  }

  @override
  Future<void> write(String accountId, String assetId, Uri url) async {
    await Directory(directory).create(recursive: true);
    final temporary = File('$directory/${const Uuid().v4()}.tmp');
    try {
      await temporary.writeAsString(
        jsonEncode({'accountId': accountId, 'url': url.toString()}),
        flush: true,
      );
      await temporary.rename(_file(assetId).path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<void> delete(String accountId, String assetId) async {
    final file = _file(assetId);
    if (await file.exists()) await file.delete();
  }
}
