import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/pdf/document_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cancelar el guardado nativo no comunica un archivo guardado', () async {
    MethodCall? received;
    const channel = MethodChannel('nala/files');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return false;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final bytes = Uint8List.fromList([37, 80, 68, 70]);
    final saved = await AndroidDocumentSaver().save(bytes, name: 'Guía.pdf');
    expect(saved, isFalse);
    expect(received!.method, 'savePdf');
    expect(received!.arguments['name'], 'Guía.pdf');
    expect(received!.arguments['bytes'], bytes);
  });
}
