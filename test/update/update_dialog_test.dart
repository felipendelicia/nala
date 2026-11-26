import 'package:apuntes/update/app_updates.dart';
import 'package:apuntes/update/github_updates.dart';
import 'package:apuntes/update/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Updates implements AppUpdates {
  _Updates({this.available, this.result = UpdateInstallResult.linuxRestart});

  final UpdateRelease? available;
  UpdateInstallResult result;
  int checks = 0;
  UpdateRelease? installed;
  bool failCheck = false;

  @override
  Future<UpdateRelease?> check() async {
    checks++;
    if (failCheck) throw StateError('offline');
    return available;
  }

  @override
  Future<UpdateInstallResult> install(UpdateRelease release) async {
    installed = release;
    return result;
  }

  @override
  void close() {}
}

final _release = UpdateRelease(
  version: '0.7.11',
  assetName: 'Nala-Linux-x64.tar.gz',
  downloadUri: Uri.parse(
    'https://github.com/felipendelicia/nala/releases/download/v0.7.11/Nala-Linux-x64.tar.gz',
  ),
  size: 100,
  sha256: List.filled(64, '0').join(),
);

Future<void> _open(WidgetTester tester, _Updates updates) async {
  await tester.pumpWidget(MaterialApp(home: UpdateDialog(updates: updates)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('informa cuando la versión instalada está al día', (
    tester,
  ) async {
    final updates = _Updates();
    await _open(tester, updates);

    expect(updates.checks, 1);
    expect(find.text('Ya tenés la última versión disponible.'), findsOneWidget);
    expect(find.text('Instalar'), findsNothing);
  });

  testWidgets('instala la versión elegida y avisa que se aplica al reabrir', (
    tester,
  ) async {
    final updates = _Updates(available: _release);
    await _open(tester, updates);

    expect(find.text('Nala 0.7.11 está disponible.'), findsOneWidget);
    expect(updates.installed, isNull);
    await tester.tap(find.text('Instalar'));
    await tester.pumpAndSettle();

    expect(updates.installed, same(_release));
    expect(
      find.text('La actualización se aplicará la próxima vez que abras Nala.'),
      findsOneWidget,
    );
  });

  testWidgets('permite repetir una búsqueda que falló', (tester) async {
    final updates = _Updates()..failCheck = true;
    await _open(tester, updates);

    expect(find.text('No se pudieron buscar actualizaciones.'), findsOneWidget);
    updates.failCheck = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(updates.checks, 2);
    expect(find.text('Ya tenés la última versión disponible.'), findsOneWidget);
  });

  testWidgets('ofrece continuar después de abrir el permiso de Android', (
    tester,
  ) async {
    final updates = _Updates(
      available: _release,
      result: UpdateInstallResult.androidPermission,
    );
    await _open(tester, updates);
    await tester.tap(find.text('Instalar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Permití que Nala instale'), findsOneWidget);
    updates.result = UpdateInstallResult.androidInstaller;
    await tester.tap(find.text('Instalar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Seguí los pasos de Android para terminar.'),
      findsOneWidget,
    );
    expect(find.text('Instalar'), findsNothing);
  });
}
