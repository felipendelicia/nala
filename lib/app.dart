import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'bootstrap.dart';
import 'library/library_screen.dart';
import 'ui/app_theme.dart';
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
  late final Future<AppServices> services = widget.services != null
      ? Future.value(widget.services)
      : _open();
  Future<AppServices> _open() async {
    cloud = await CloudController.open(
      (await getApplicationSupportDirectory()).path,
      auth: const AuthConfig().create(),
    );
    return cloud!.services;
  }

  @override
  void dispose() {
    unawaited(
      services
          .then((_) async {
            await cloud?.close();
          })
          .catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nala',
    debugShowCheckedModeBanner: false,
    theme: nalaTheme(),
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
