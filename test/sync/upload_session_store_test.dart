import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/sync/upload_session_store.dart';

void main() {
  test(
    'una sesión dañada se descarta para que la subida pueda reiniciarse',
    () async {
      final dir = await Directory.systemTemp.createTemp('nala-session-');
      final store = FileUploadSessionStore(dir.path);
      final id = 'a' * 64;
      try {
        for (final json in ['[]', '{"accountId":"A","url":null}', '{']) {
          await File('${dir.path}/$id.json').writeAsString(json);
          expect(await store.read('A', id), isNull);
          expect(await File('${dir.path}/$id.json').exists(), isFalse);
        }
        final url = Uri.parse(
          'https://www.googleapis.com/upload/session-fixture',
        );
        await store.write('A', id, url);
        expect(await store.read('B', id), isNull);
        expect(await store.read('A', id), url);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
