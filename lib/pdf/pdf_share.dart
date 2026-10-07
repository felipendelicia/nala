import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

enum ShareTarget { system, copyFile, email }

abstract interface class PdfShare {
  List<ShareTarget> get targets;
  Future<bool> share(
    Uint8List bytes, {
    required String name,
    ShareTarget target = ShareTarget.system,
  });
}

class NativePdfShare implements PdfShare {
  NativePdfShare({Future<Directory> Function()? temporaryDirectory})
    : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  static const _channel = MethodChannel('nala/share');
  @override
  List<ShareTarget> get targets => Platform.isAndroid
      ? [ShareTarget.system]
      : [ShareTarget.copyFile, ShareTarget.email];
  @override
  Future<bool> share(
    Uint8List bytes, {
    required String name,
    ShareTarget target = ShareTarget.system,
  }) async {
    if (bytes.length < 5 ||
        ascii.decode(bytes.sublist(0, 5), allowInvalid: true) != '%PDF-') {
      throw const FormatException('PDF vacío o inválido.');
    }
    final root = Directory(
      p.join((await _temporaryDirectory()).path, 'nala-share'),
    );
    await root.create(recursive: true);
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('La carpeta temporal no es válida.');
    }
    await _privatePath(root.path, '700');
    await _removeOldSessions(root);
    final session = await Directory(
      p.join(root.path, const Uuid().v4()),
    ).create();
    await _privatePath(session.path, '700');
    final file = await File(
      p.join(session.path, _fileName(name)),
    ).writeAsBytes(bytes, flush: true);
    await _privatePath(file.path, '600');
    // Keep the file after opening the chooser: receivers may read it later.
    if (target == ShareTarget.email) {
      final process = await Process.start('xdg-email', [
        '--subject',
        name,
        '--attach',
        file.path,
      ]);
      process.stdout.drain<void>();
      process.stderr.drain<void>();
      return await process.exitCode.timeout(
            const Duration(seconds: 2),
            onTimeout: () => 0,
          ) ==
          0;
    }
    return await _channel.invokeMethod<bool>(
          target == ShareTarget.copyFile ? 'copyPdf' : 'sharePdf',
          {
            'path': file.path,
            'name': p.basename(file.path),
            'mimeType': 'application/pdf',
          },
        ) ??
        false;
  }

  Future<void> _privatePath(String path, String mode) async {
    // Android's cache is app-private already. Linux temporary roots may be /tmp.
    if (!Platform.isLinux) return;
    final result = await Process.run('chmod', [mode, '--', path]);
    if (result.exitCode != 0) {
      throw const FileSystemException(
        'No se pudo proteger el archivo temporal.',
      );
    }
  }

  Future<void> _removeOldSessions(Directory root) async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      try {
        final files = await entity.list(followLinks: false).toList();
        if (files.isNotEmpty && files.every((f) => f is File)) {
          var expired = true;
          for (final file in files) {
            if (!(await file.stat()).modified.isBefore(cutoff)) {
              expired = false;
              break;
            }
          }
          if (expired) await entity.delete(recursive: true);
        }
      } on FileSystemException {
        /* Cleanup cannot prevent sharing the current PDF. */
      }
    }
  }

  String _fileName(String name) {
    var clean = name
        .replaceAll(RegExp(r'[\x00-\x1f\x7f\\/:*?"<>|]'), '_')
        .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')
        .trim()
        .replaceFirst(RegExp(r'^\.+'), '');
    if (clean.isEmpty) clean = 'Apunte';
    final result = StringBuffer();
    var length = 0;
    for (final rune in clean.runes) {
      final text = String.fromCharCode(rune),
          bytes = utf8.encode(String.fromCharCode(rune)).length;
      if (length + bytes > 160) break;
      result.write(text);
      length += bytes;
    }
    return '$result.pdf';
  }
}
