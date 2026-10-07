import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:apuntes/ui/app_theme.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/library/library_controller.dart';
import '../support/memory_repository.dart';

void main() {
  for (final size in [
    const Size(1200, 800),
    const Size(800, 1200),
    const Size(1440, 900),
  ]) {
    testWidgets('biblioteca vacía usable en $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = MemoryRepository();
      final services = AppServices(
        root: '/unused',
        deviceId: 'pc',
        repository: repository,
        assets: FileAssetStore('/unused/assets'),
        library: LibraryController(repository: repository, deviceId: 'pc'),
      );
      await services.library.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: nalaTheme(brightness: Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: LibraryScreen(services: services),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Crear cuaderno'), findsOneWidget);
      await tester.tap(find.text('Crear cuaderno'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Nombre del cuaderno'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await services.close();
    });
  }
}
