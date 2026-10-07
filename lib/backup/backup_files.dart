import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import '../pdf/document_files.dart';

class SelectedBackup {
  const SelectedBackup({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;
}

abstract interface class BackupFiles {
  Future<SelectedBackup?> open();
  Future<bool> save(Uint8List bytes, {required String name});
}

class NativeBackupFiles implements BackupFiles {
  static const _type = XTypeGroup(
    label: 'Backup de Nala',
    extensions: ['zip'],
    mimeTypes: ['application/zip', 'application/x-zip-compressed'],
  );
  @override
  Future<SelectedBackup?> open() async {
    final file = await openFile(acceptedTypeGroups: [_type]);
    if (file == null) return null;
    if (await file.length() > 128 * 1024 * 1024) {
      throw const FormatException('El backup supera los 128 MB');
    }
    return SelectedBackup(bytes: await file.readAsBytes(), name: file.name);
  }

  @override
  Future<bool> save(Uint8List bytes, {required String name}) async {
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final fileName = safe.toLowerCase().endsWith('.nala.zip')
        ? safe
        : '$safe.nala.zip';
    if (Platform.isAndroid) {
      return AndroidDocumentSaver().save(
        bytes,
        name: fileName,
        mimeType: 'application/zip',
      );
    }
    final destination = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [_type],
    );
    if (destination == null) return false;
    await XFile.fromData(
      bytes,
      mimeType: 'application/zip',
      name: fileName,
    ).saveTo(destination.path);
    return true;
  }
}
