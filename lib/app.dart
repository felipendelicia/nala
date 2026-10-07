import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'bootstrap.dart';
import 'library/library_screen.dart';
import 'ui/app_theme.dart';
import 'ui/appearance.dart';
import 'account/cloud_controller.dart';
import 'account/auth_config.dart';

class NalaApp extends StatefulWidget {
  const NalaApp({super.key, this.services});
  final AppServices? services;
  @override
  State<NalaApp> createState() => _NalaAppState();
}

class _NalaAppState extends State<NalaApp> {
  CloudController? cloud;
  AppearanceController? appearance;
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
    final root = (await getApplicationSupportDirectory()).path;
    appearance = await AppearanceController.open(root);
    appearance!.addListener(themeChanged);
    themeChanged();
    cloud = await CloudController.open(root, auth: const AuthConfig().create());
    return cloud!.services;
  }

  @override
  void dispose() {
    unawaited(
      services
          .then((_) async {
            appearance?.removeListener(themeChanged);
            appearance?.dispose();
            await cloud?.close();
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
            builder: (_, _) => Stack(
              children: [
                LibraryScreen(
                  key: ValueKey(cloud!.services.root),
                  services: cloud!.services,
                  cloud: cloud,
                ),
                if (cloud!.busy)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black26,
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                const Text('Conectando con Google Drive…'),
                                TextButton(
                                  onPressed: () =>
                                      unawaited(cloud!.cancelConnection()),
                                  child: const Text('Cancelar'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text(
                'No se pudieron abrir tus apuntes. Revisá el espacio del dispositivo y reiniciá Nala.',
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    ),
  );
}
