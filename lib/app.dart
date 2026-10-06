import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'bootstrap.dart';
import 'library/library_screen.dart';
import 'ui/app_theme.dart';

class NalaApp extends StatefulWidget {
  const NalaApp({super.key, this.services});
  final AppServices? services;
  @override
  State<NalaApp> createState() => _NalaAppState();
}

class _NalaAppState extends State<NalaApp> {
  late final Future<AppServices> services = widget.services != null
      ? Future.value(widget.services)
      : _open();
  Future<AppServices> _open() async =>
      AppServices.open((await getApplicationSupportDirectory()).path);
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nala',
    debugShowCheckedModeBanner: false,
    theme: nalaTheme(),
    home: FutureBuilder<AppServices>(
      future: services,
      builder: (context, snapshot) {
        if (snapshot.hasData) return LibraryScreen(services: snapshot.data!);
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
