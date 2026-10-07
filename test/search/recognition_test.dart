import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/search/recognition_service.dart';
import '../support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/nala/ink');
  test(
    'recognition sends the stored stroke coordinates to the native engine',
    () async {
      Object? ink;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'status') {
              return {'available': true, 'downloaded': true};
            }
            if (call.method == 'recognize') {
              ink = call.arguments;
              return 'Álgebra';
            }
            throw PlatformException(code: 'UNEXPECTED');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final recognizer = AndroidInkRecognition(channel: channel);
      expect(
        await recognizer.recognize(fixtureNotebook().pages.single),
        'Álgebra',
      );
      final arguments = ink as Map;
      expect(((arguments['strokes'] as List).single as List).first, {
        'x': 10.0,
        'y': 20.0,
      });
      expect(((arguments['strokes'] as List).single as List).last, {
        'x': 30.0,
        'y': 40.0,
      });
    },
  );
  test('missing model blocks recognition until explicit download', () async {
    var downloaded = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'status') {
            return {'available': true, 'downloaded': downloaded};
          }
          if (call.method == 'download') {
            downloaded = true;
            return true;
          }
          if (call.method == 'recognize') return 'Texto';
          throw PlatformException(code: 'UNEXPECTED');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final recognizer = AndroidInkRecognition(channel: channel);
    await expectLater(
      recognizer.recognize(fixtureNotebook().pages.single),
      throwsStateError,
    );
    expect(downloaded, isFalse);
    await recognizer.downloadModel();
    expect(await recognizer.recognize(fixtureNotebook().pages.single), 'Texto');
  });
}
