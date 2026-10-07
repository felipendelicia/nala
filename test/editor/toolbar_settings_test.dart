import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/editor/toolbar_preferences.dart';
import 'package:apuntes/editor/toolbar_settings_dialog.dart';

void main() {
  testWidgets('dragging first toolbar access down changes saved order', (
    tester,
  ) async {
    ToolbarLayout? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showToolbarSettings(
                  context,
                  ToolbarLayout.defaults(),
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    final handles = find.byType(ReorderableDragStartListener);
    final first = tester.getCenter(handles.at(0));
    final second = tester.getCenter(handles.at(1));
    final drag = await tester.startGesture(first);
    await drag.moveBy(const Offset(0, 24));
    await tester.pump(const Duration(milliseconds: 100));
    await drag.moveTo(first + Offset(0, (second.dy - first.dy) * .75));
    await tester.pump(const Duration(milliseconds: 300));
    await drag.moveTo(
      second + const Offset(0, 20),
      timeStamp: const Duration(milliseconds: 200),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await drag.up();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(saved!.order.take(2), [
      ToolbarAction.highlighter,
      ToolbarAction.pen,
    ]);
  });
}
