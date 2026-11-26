import 'dart:io';

import 'package:flutter/services.dart';

class AndroidUpdate {
  const AndroidUpdate();

  static const _channel = MethodChannel('nala/update');

  Future<String> installedVersion() async {
    final version = await _channel.invokeMethod<String>('installedVersion');
    return version ??
        (throw PlatformException(
          code: 'VERSION_UNAVAILABLE',
          message: 'No se pudo leer la versión de Nala.',
        ));
  }

  /// Returns true if Android opened the installer, or false if it opened the
  /// settings screen for granting Nala permission to request installations.
  Future<bool> install(File apk, String version) async {
    final launched = await _channel.invokeMethod<bool>('install', {
      'path': apk.path,
      'version': version,
    });
    return launched ??
        (throw PlatformException(
          code: 'INSTALL_FAILED',
          message: 'Android no pudo abrir el instalador de Nala.',
        ));
  }
}
