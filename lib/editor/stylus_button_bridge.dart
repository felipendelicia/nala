import 'dart:async';
import 'package:flutter/services.dart';

/// Android forwards button edges omitted by Flutter's generic-motion handling.
/// Coordinates remain on Flutter's pointer stream; no channel roundtrip per dot.
class StylusButtonBridge {
  static const _channel = MethodChannel('nala/stylus');
  static StylusButtonBridge? _owner;
  bool _active = false;
  void start({
    required void Function(bool) onButton,
    required void Function() onReset,
    required void Function(bool) onAvailability,
  }) {
    _owner?._active = false;
    _owner = this;
    _active = true;
    _channel.setMethodCallHandler((call) async {
      if (!_active) return;
      if (call.method == 'button' && call.arguments is bool) {
        onAvailability(true);
        onButton(call.arguments as bool);
      }
      if (call.method == 'reset') onReset();
    });
    unawaited(
      _listen(true).then((available) {
        if (_active) onAvailability(available);
      }),
    );
  }

  void dispose() {
    _active = false;
    if (!identical(_owner, this)) return;
    _owner = null;
    _channel.setMethodCallHandler(null);
    unawaited(_listen(false).then((_) {}));
  }

  Future<bool> _listen(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('listen', enabled);
      return true;
    } on MissingPluginException {
      /* Pointer buttons still work on desktop. */
    } on PlatformException {
      /* Fall back to the ordinary stylus pointer stream. */
    }
    return false;
  }
}
