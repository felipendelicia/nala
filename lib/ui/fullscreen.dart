import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FullscreenController extends ChangeNotifier {
  FullscreenController() {
    _channel.setMethodCallHandler(_onPlatformCall);
    unawaited(_readState());
  }

  static const _channel = MethodChannel('nala/fullscreen');
  bool _available = false;
  bool _enabled = false;
  bool _changing = false;
  bool _disposed = false;
  int _stateChanges = 0;

  bool get available => _available;
  bool get enabled => _enabled;
  bool get changing => _changing;

  Future<void> _readState() async {
    try {
      final enabled = await _channel.invokeMethod<bool>('getFullscreen');
      if (_disposed || enabled == null) return;
      if (_stateChanges == 0) _enabled = enabled;
      _available = true;
      notifyListeners();
    } on MissingPluginException {
      // Some runners do not provide a window to configure.
    } on PlatformException {
      // Leave the fullscreen controls unavailable when initialization fails.
    }
  }

  Future<void> _onPlatformCall(MethodCall call) async {
    if (call.method != 'fullscreenChanged' || call.arguments is! bool) return;
    final enabled = call.arguments as bool;
    _stateChanges++;
    if (_enabled != enabled) {
      _enabled = enabled;
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (!_available || _changing) return;
    final enabled = !_enabled;
    final previousChanges = _stateChanges;
    _changing = true;
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('setFullscreen', enabled);
      if (_stateChanges == previousChanges) _enabled = enabled;
    } finally {
      _changing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

class FullscreenScope extends InheritedNotifier<FullscreenController> {
  const FullscreenScope({
    super.key,
    required FullscreenController controller,
    required super.child,
  }) : super(notifier: controller);

  static FullscreenController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FullscreenScope>()?.notifier;
}

Future<void> toggleFullscreen(
  BuildContext context,
  FullscreenController controller,
) async {
  try {
    await controller.toggle();
  } catch (error) {
    if (error is! PlatformException && error is! MissingPluginException) {
      rethrow;
    }
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('No se pudo cambiar la pantalla completa.'),
        ),
      );
    }
  }
}
