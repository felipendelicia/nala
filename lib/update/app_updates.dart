import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'android_update.dart';
import 'github_updates.dart';
import 'linux_update.dart';

enum UpdateInstallResult { androidInstaller, androidPermission, linuxRestart }

abstract interface class AppUpdates {
  Future<UpdateRelease?> check();
  Future<UpdateInstallResult> install(UpdateRelease release);
  void close();
}

class NativeAppUpdates implements AppUpdates {
  static bool get isSupported => Platform.isAndroid || Platform.isLinux;

  static const _android = AndroidUpdate();
  static const _linux = LinuxUpdate();

  static Future<String> installedVersion() => Platform.isAndroid
      ? _android.installedVersion()
      : _linux.installedVersion();

  final _github = GitHubUpdates();
  File? _uninstalledApk;

  @override
  Future<UpdateRelease?> check() async => _github.check(
    installedVersion: await installedVersion(),
    target: Platform.isAndroid
        ? UpdateTarget.androidArm64
        : UpdateTarget.linuxX64,
  );

  @override
  Future<UpdateInstallResult> install(UpdateRelease release) async {
    if (Platform.isLinux) await _linux.ensureCanStage();
    final cache = await getTemporaryDirectory();
    final directory = Directory(p.join(cache.path, 'nala-updates'));
    if (Platform.isAndroid) {
      var apk = _uninstalledApk;
      if (apk == null || !await apk.exists()) {
        apk = _uninstalledApk = await _github.download(
          release,
          directory: directory,
        );
      }
      try {
        if (!await _android.install(apk, release.version)) {
          return UpdateInstallResult.androidPermission;
        }
        // Android reads the APK after the installer opens.
        _uninstalledApk = null;
        return UpdateInstallResult.androidInstaller;
      } catch (_) {
        _uninstalledApk = null;
        await _discard(apk);
        rethrow;
      }
    }

    final package = await _github.download(release, directory: directory);
    try {
      await _linux.stage(package, release.version);
      return UpdateInstallResult.linuxRestart;
    } finally {
      await _discard(package);
    }
  }

  @override
  void close() {
    _github.close();
    final apk = _uninstalledApk;
    _uninstalledApk = null;
    if (apk != null) unawaited(_discard(apk));
  }

  Future<void> _discard(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // An evicted cache file or cleanup failure does not change the result.
    }
  }
}
