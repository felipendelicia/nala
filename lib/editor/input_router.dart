import 'dart:math';

enum InputDevice { pen, touch, mouse }

class InputSample {
  const InputSample({
    required this.pointerId,
    required this.device,
    required this.position,
    required this.pressure,
    required this.buttons,
  });
  final int pointerId, buttons;
  final InputDevice device;
  final Point<double> position;
  final double pressure;
}

class InputRouter {
  InputRouter({
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    required this.onNavigate,
    this.onStylusButton,
    this.onReset,
  });
  final void Function(InputSample) onBegin, onUpdate, onEnd;
  final void Function() onCancel;
  final void Function(double dx, double dy, double factor, Point<double> anchor)
  onNavigate;
  final void Function(bool)? onStylusButton;
  final void Function()? onReset;
  InputSample? _inkSample;
  bool _buttonPressed = false;
  int? _inkPointer, _middlePointer;
  bool readOnly = false;
  bool nativeButtonEvents = false;
  Point<double>? _middlePosition;
  final Map<int, Point<double>> _touches = {};
  bool get isWriting => _inkPointer != null;
  void down(InputSample event) {
    _observeButton(event);
    if (readOnly &&
        (event.device == InputDevice.pen ||
            (event.device == InputDevice.mouse && event.buttons == 1))) {
      if (_middlePointer == null) {
        _middlePointer = event.pointerId;
        _middlePosition = event.position;
      }
      return;
    }
    if (event.device == InputDevice.pen ||
        (event.device == InputDevice.mouse && event.buttons == 1)) {
      if (_inkPointer != null) return;
      _inkPointer = event.pointerId;
      _inkSample = event;
      _touches.clear();
      onBegin(event);
    } else if (event.device == InputDevice.touch && _inkPointer == null) {
      _touches[event.pointerId] = event.position;
    } else if (event.device == InputDevice.mouse &&
        event.buttons == 4 &&
        _inkPointer == null) {
      _middlePointer = event.pointerId;
      _middlePosition = event.position;
    }
  }

  void move(InputSample event) {
    _observeButton(event);
    if (_inkPointer == event.pointerId) {
      onUpdate(event);
      _inkSample = event;
      return;
    }
    if (_inkPointer != null) return;
    if (_middlePointer == event.pointerId) {
      final before = _middlePosition!;
      _middlePosition = event.position;
      onNavigate(
        event.position.x - before.x,
        event.position.y - before.y,
        1,
        before,
      );
      return;
    }
    if (!_touches.containsKey(event.pointerId)) return;
    final before = _center(), oldDistance = _distance();
    _touches[event.pointerId] = event.position;
    final after = _center(), distance = _distance();
    onNavigate(
      after.x - before.x,
      after.y - before.y,
      oldDistance > 0 && distance > 0 ? distance / oldDistance : 1,
      before,
    );
  }

  void up(InputSample event) {
    if (_inkPointer == event.pointerId) {
      _inkPointer = null;
      _inkSample = null;
      onEnd(event);
    }
    _touches.remove(event.pointerId);
    if (_middlePointer == event.pointerId) {
      _middlePointer = null;
      _middlePosition = null;
    }
  }

  void cancel(int pointerId) {
    if (_inkPointer == pointerId) {
      _inkPointer = null;
      _inkSample = null;
      onCancel();
      _resetButton();
    }
    _touches.remove(pointerId);
    if (_middlePointer == pointerId) {
      _middlePointer = null;
      _middlePosition = null;
    }
  }

  void reset() {
    if (_inkPointer != null) onCancel();
    _inkPointer = null;
    _inkSample = null;
    _resetButton();
    _middlePointer = null;
    _middlePosition = null;
    _touches.clear();
  }

  void _resetButton() {
    _buttonPressed = false;
    onReset?.call();
  }

  void _observeButton(InputSample event) {
    if (!nativeButtonEvents && event.device == InputDevice.pen) {
      stylusButton((event.buttons & 2) != 0);
    }
  }

  void stylusButton(bool pressed) {
    if (_buttonPressed == pressed) return;
    _buttonPressed = pressed;
    if (!readOnly) onStylusButton?.call(pressed);
  }

  /// Finish using the old tool, then restart at the same contact point. Keep
  /// pointer ownership so a palm cannot take over between these segments.
  void changeInkTool(void Function() change) {
    final contact = _inkSample;
    if (contact != null) onEnd(contact);
    change();
    if (contact != null) onBegin(contact);
  }

  void hover(InputSample event) => _observeButton(event);
  Point<double> _center() {
    var x = 0.0, y = 0.0;
    for (final p in _touches.values) {
      x += p.x;
      y += p.y;
    }
    return Point(x / _touches.length, y / _touches.length);
  }

  double _distance() {
    if (_touches.length != 2) return 0;
    return _touches.values.first.distanceTo(_touches.values.last);
  }
}
