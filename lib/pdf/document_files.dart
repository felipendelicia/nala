import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

class SelectedPdf {
  SelectedPdf({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;
}

abstract interface class DocumentFiles {
  Future<SelectedPdf?> openPdf();
  Future<bool> savePdf(Uint8List bytes, {required String name});
}

class AndroidDocumentSaver {
  static const _channel = MethodChannel('nala/files');
  Future<bool> save(
    Uint8List bytes, {
    required String name,
    String mimeType = 'application/pdf',
  }) async =>
      await _channel.invokeMethod<bool>(
        mimeType == 'application/pdf' ? 'savePdf' : 'saveDocument',
        {
          'bytes': bytes,
          'name': name,
          if (mimeType != 'application/pdf') 'mimeType': mimeType,
        },
      ) ??
      false;
}

class NativeDocumentFiles implements DocumentFiles {
  static const _type = XTypeGroup(
    label: 'PDF',
    extensions: ['pdf'],
    mimeTypes: ['application/pdf'],
  );
  @override
  Future<SelectedPdf?> openPdf() async {
    final file = await openFile(acceptedTypeGroups: [_type]);
    if (file == null) return null;
    return SelectedPdf(bytes: await file.readAsBytes(), name: file.name);
  }

  @override
  Future<bool> savePdf(Uint8List bytes, {required String name}) async {
    final fileName =
        '${name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}.pdf';
    if (Platform.isAndroid) {
      return AndroidDocumentSaver().save(bytes, name: fileName);
    }
    final result = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [_type],
    );
    if (result == null) return false;
    await XFile.fromData(
      bytes,
      mimeType: 'application/pdf',
      name: fileName,
    ).saveTo(result.path);
    return true;
  }
}
