import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/editor/input_router.dart';

InputSample sample(
  int id,
  InputDevice device,
  double x,
  double y, {
  int buttons = 1,
}) => InputSample(
  pointerId: id,
  device: device,
  position: Point(x, y),
  pressure: .5,
  buttons: buttons,
);
void main() {
  test('la palma no mueve la hoja durante un trazo', () {
    var completed = 0, navigation = 0;
    final router = InputRouter(
      onBegin: (_) {},
      onUpdate: (_) {},
      onEnd: (_) => completed++,
      onCancel: () {},
      onNavigate: (dx, dy, zoom, anchor) => navigation++,
    );
    router.down(sample(1, InputDevice.pen, 10, 10));
    router.down(sample(2, InputDevice.touch, 30, 30));
    router.move(sample(2, InputDevice.touch, 50, 50));
    router.move(sample(1, InputDevice.pen, 20, 20));
    router.up(sample(1, InputDevice.pen, 20, 20));
    expect(completed, 1);
    expect(navigation, 0);
  });
  test('cancelar descarta el trazo y un dedo solo navega', () {
    var completed = 0, canceled = 0;
    var moved = 0.0;
    final router = InputRouter(
      onBegin: (_) {},
      onUpdate: (_) {},
      onEnd: (_) => completed++,
      onCancel: () => canceled++,
      onNavigate: (dx, dy, zoom, anchor) => moved += dx,
    );
    router.down(sample(1, InputDevice.pen, 10, 10));
    router.cancel(1);
    router.down(sample(2, InputDevice.touch, 30, 30));
    router.move(sample(2, InputDevice.touch, 50, 30));
    router.up(sample(2, InputDevice.touch, 50, 30));
    expect(completed, 0);
    expect(canceled, 1);
    expect(moved, 20);
  });
  test('dos dedos amplían y el botón central desplaza', () {
    var factor = 1.0, delta = 0.0;
    final router = InputRouter(
      onBegin: (_) {},
      onUpdate: (_) {},
      onEnd: (_) {},
      onCancel: () {},
      onNavigate: (dx, dy, zoom, anchor) {
        factor *= zoom;
        delta += dx;
      },
    );
    router.down(sample(1, InputDevice.touch, 0, 0));
    router.down(sample(2, InputDevice.touch, 10, 0));
    router.move(sample(2, InputDevice.touch, 20, 0));
    expect(factor, 2);
    router.reset();
    delta = 0;
    router.down(sample(3, InputDevice.mouse, 10, 20, buttons: 4));
    router.move(sample(3, InputDevice.mouse, 30, 20, buttons: 4));
    expect(delta, 20);
  });
}
