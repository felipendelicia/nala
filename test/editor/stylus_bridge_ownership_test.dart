import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/editor/stylus_button_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'disposing an inactive pane cannot detach active native stylus events',
    () async {
      const channel = MethodChannel('nala/stylus');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final requests = <bool>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'listen') requests.add(call.arguments as bool);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      var oldButtons = 0, newButtons = 0;
      final old = StylusButtonBridge(), current = StylusButtonBridge();
      old.start(
        onButton: (_) => oldButtons++,
        onReset: () {},
        onAvailability: (_) {},
      );
      current.start(
        onButton: (_) => newButtons++,
        onReset: () {},
        onAvailability: (_) {},
      );
      old.dispose();
      final done = Completer<void>();
      messenger.handlePlatformMessage(
        'nala/stylus',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('button', true),
        ),
        (_) => done.complete(),
      );
      await done.future;
      expect(oldButtons, 0);
      expect(newButtons, 1);
      expect(requests.where((value) => !value), isEmpty);
      current.dispose();
    },
  );
}
