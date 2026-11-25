import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'bootstrap.dart';
import 'library/library_screen.dart';
import 'ui/app_theme.dart';
import 'ui/appearance.dart';
import 'account/cloud_controller.dart';

class NalaApp extends StatefulWidget {
  const NalaApp({super.key, this.services});
  final AppServices? services;
  @override
  State<NalaApp> createState() => _NalaAppState();
}

class _NalaAppState extends State<NalaApp> {
  CloudController? cloud;
  AppearanceController? appearance;
  RandomAccessFile? _libraryLock;
  Future<AppServices> loadAppearance(AppServices services) async {
    appearance = await AppearanceController.open(services.root);
    appearance!.addListener(themeChanged);
    themeChanged();
    return services;
  }

  void themeChanged() {
    if (mounted) setState(() {});
  }

  late final Future<AppServices> services = widget.services != null
      ? loadAppearance(widget.services!)
      : _open();
  Future<AppServices> _open() async {
    final directory = await getApplicationSupportDirectory();
    if (Platform.isLinux) {
      await directory.create(recursive: true);
      final lock = await File(
        p.join(directory.path, 'nala-app.lock'),
      ).open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.exclusive);
      } on FileSystemException catch (error) {
        await lock.close();
        if (error.osError?.errorCode == 11 || error.osError?.errorCode == 13) {
          throw const _LibraryAlreadyOpen();
        }
        rethrow;
      }
      _libraryLock = lock;
    }
    try {
      appearance = await AppearanceController.open(directory.path);
      appearance!.addListener(themeChanged);
      themeChanged();
      cloud = await CloudController.open(directory.path);
      return cloud!.services;
    } catch (_) {
      await _libraryLock?.close();
      _libraryLock = null;
      rethrow;
    }
  }

  @override
  void dispose() {
    unawaited(
      services
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .whenComplete(() async {
            appearance?.removeListener(themeChanged);
            appearance?.dispose();
            try {
              await cloud?.close();
            } finally {
              await _libraryLock?.close();
            }
          })
          .catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => appearance == null
      ? buildApp()
      : AppearanceScope(controller: appearance!, child: buildApp());
  Widget buildApp() => MaterialApp(
    title: 'Nala',
    debugShowCheckedModeBanner: false,
    theme: nalaTheme(),
    darkTheme: nalaTheme(brightness: Brightness.dark),
    themeMode: appearance?.mode ?? ThemeMode.system,
    home: FutureBuilder<AppServices>(
      future: services,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          if (cloud == null) return LibraryScreen(services: snapshot.data!);
          return AnimatedBuilder(
            animation: cloud!,
            builder: (_, _) => LibraryScreen(
              key: ValueKey(cloud!.services.root),
              services: cloud!.services,
              cloud: cloud,
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                snapshot.error is _LibraryAlreadyOpen
                    ? 'Nala ya tiene abierta esta biblioteca en otra ventana.'
                    : 'No se pudieron abrir tus apuntes. Revisá el espacio del dispositivo y reiniciá Nala.',
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    ),
  );
}

class _LibraryAlreadyOpen implements Exception {
  const _LibraryAlreadyOpen();
}
