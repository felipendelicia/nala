import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cerrar el proceso de Nala termina también su proceso de audio',
    () async {
      final debug = File('build/linux/x64/debug/bundle/apuntes');
      final release = File('build/linux/x64/release/bundle/apuntes');
      final binary = await debug.exists() ? debug : release;
      expect(
        await binary.exists(),
        isTrue,
        reason: 'Compilar Linux antes de las pruebas.',
      );
      final result = await Process.run('python3', [
        'test/support/audio_parent_guard.py',
        binary.absolute.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    },
  );
}
