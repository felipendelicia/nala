import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/ui/appearance.dart';
import 'package:apuntes/ui/app_theme.dart';
import 'package:apuntes/app.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/library/library_controller.dart';
import 'package:apuntes/library/library_screen.dart';
import '../test/support/memory_repository.dart';

void main() {
  test('claro y oscuro usan blanco negro y grises en toda la interfaz', () {
    for (final brightness in Brightness.values) {
      final theme = nalaTheme(brightness: brightness);
      final scheme = theme.colorScheme;
      final colors = [
        theme.scaffoldBackgroundColor,
        scheme.primary,
        scheme.onPrimary,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        scheme.secondary,
        scheme.onSecondary,
        scheme.secondaryContainer,
        scheme.tertiary,
        scheme.tertiaryContainer,
        scheme.error,
        scheme.errorContainer,
        scheme.onError,
        scheme.onErrorContainer,
        scheme.surface,
        scheme.onSurface,
        scheme.onSurfaceVariant,
        scheme.surfaceContainer,
        scheme.surfaceContainerLow,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerHighest,
        scheme.outline,
        scheme.outlineVariant,
        scheme.inversePrimary,
        scheme.inverseSurface,
        scheme.onInverseSurface,
        theme.inputDecorationTheme.fillColor!,
        nalaSidebar,
        nalaAnnotation,
      ];
      for (final color in colors) {
        final rgb = color.toARGB32();
        expect(
          (rgb >> 16) & 255,
          (rgb >> 8) & 255,
          reason: 'Los controles no deben tener tintes de color.',
        );
        expect((rgb >> 8) & 255, rgb & 255);
      }
      expect(
        theme.scaffoldBackgroundColor,
        brightness == Brightness.dark ? Colors.black : Colors.white,
      );
      final foreground = scheme.onPrimary.computeLuminance();
      final background = scheme.primary.computeLuminance();
      expect(
        (math.max(foreground, background) + .05) /
            (math.min(foreground, background) + .05),
        greaterThanOrEqualTo(7),
      );
    }
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'tema oscuro y sistema se conservan al reiniciar sin tocar los apuntes',
    () async {
      final root = await Directory.systemTemp.createTemp('nala-theme-');
      addTearDown(() => root.delete(recursive: true));
      final notes = await File(
        '${root.path}/notas-personales.txt',
      ).writeAsString('preservar');
      final settings = await AppearanceController.open(root.path);
      expect(settings.mode, ThemeMode.system);
      await settings.setMode(ThemeMode.dark);
      final reopened = await AppearanceController.open(root.path);
      expect(reopened.mode, ThemeMode.dark);
      await reopened.setMode(ThemeMode.system);
      expect(
        (await AppearanceController.open(root.path)).mode,
        ThemeMode.system,
      );
      expect(await notes.readAsString(), 'preservar');
      await File(
        '${root.path}/appearance.json',
      ).writeAsString('archivo incompleto');
      expect(
        (await AppearanceController.open(root.path)).mode,
        ThemeMode.system,
      );
      for (final invalid in ['null', '[]', '42', '{"theme":"unknown"}']) {
        await File('${root.path}/appearance.json').writeAsString(invalid);
        final recovered = await AppearanceController.open(root.path);
        expect(recovered.mode, ThemeMode.system);
        recovered.dispose();
      }
      settings.dispose();
      reopened.dispose();
    },
  );
  testWidgets('Apariencia cambia toda la biblioteca y se guarda', (
    tester,
  ) async {
    late Directory root;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('nala-theme-ui-');
    });
    final repository = MemoryRepository();
    final services = AppServices(
      root: root.path,
      deviceId: 'pc',
      repository: repository,
      assets: FileAssetStore('${root.path}/assets'),
      library: LibraryController(repository: repository, deviceId: 'pc'),
    );
    await tester.pumpWidget(NalaApp(services: services));
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (find.byType(LibraryScreen).evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Apariencia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(LibraryScreen))).brightness,
      Brightness.dark,
    );
    var persisted = false;
    final writeDeadline = DateTime.now().add(const Duration(seconds: 10));
    while (!persisted && DateTime.now().isBefore(writeDeadline)) {
      await tester.pump();
      persisted = (await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final file = File('${root.path}/appearance.json');
        return await file.exists() &&
            (await file.readAsString()).contains('dark');
      }))!;
    }
    expect(persisted, isTrue);
    await tester.runAsync(() async {
      final saved = await AppearanceController.open(root.path);
      expect(saved.mode, ThemeMode.dark);
      saved.dispose();
    });
    await tester.tap(find.byTooltip('Apariencia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claro'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(LibraryScreen))).brightness,
      Brightness.light,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => root.delete(recursive: true));
    await services.close();
  });
}
