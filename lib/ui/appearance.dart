import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class AppearanceController extends ChangeNotifier {
  AppearanceController._(this.file, this.mode);
  final File file;
  ThemeMode mode;
  Future<void> _writes = Future.value();
  static Future<AppearanceController> open(String root) async {
    final file = File(p.join(root, 'appearance.json'));
    var mode = ThemeMode.system;
    try {
      final decoded = jsonDecode(await file.readAsString());
      final data = decoded is Map ? decoded : const {};
      mode = ThemeMode.values.firstWhere(
        (v) => v.name == data['theme'],
        orElse: () => ThemeMode.system,
      );
    } on FileSystemException {
      /* A new library starts with the system theme. */
    } on FormatException {
      /* Recover a interrupted settings write. */
    } on TypeError {
      /* Old or invalid settings cannot hide the library. */
    }
    return AppearanceController._(file, mode);
  }

  Future<void> setMode(ThemeMode value) {
    mode = value;
    notifyListeners();
    _writes = _writes.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      final staged = File('${file.path}.new');
      await staged.writeAsString(
        jsonEncode({'theme': value.name}),
        flush: true,
      );
      await staged.rename(file.path);
    });
    return _writes;
  }
}

class AppearanceScope extends InheritedNotifier<AppearanceController> {
  const AppearanceScope({
    super.key,
    required AppearanceController controller,
    required super.child,
  }) : super(notifier: controller);
  static AppearanceController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
}

class AppearanceButton extends StatelessWidget {
  const AppearanceButton({super.key, this.beforeChange});
  final VoidCallback? beforeChange;
  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.of(context);
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Apariencia',
      enabled: appearance != null,
      icon: Icon(
        Theme.of(context).brightness == Brightness.dark
            ? Icons.dark_mode_outlined
            : Icons.light_mode_outlined,
      ),
      initialValue: appearance?.mode,
      onSelected: (mode) async {
        beforeChange?.call();
        try {
          await appearance?.setMode(mode);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Tema aplicado. No se pudo guardar la preferencia.',
                ),
              ),
            );
          }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: ThemeMode.system, child: Text('Seguir sistema')),
        PopupMenuItem(value: ThemeMode.light, child: Text('Claro')),
        PopupMenuItem(value: ThemeMode.dark, child: Text('Oscuro')),
      ],
    );
  }
}
