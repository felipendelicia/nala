import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/editor/toolbar_preferences.dart';

void main() {
  test('toolbar order, visibility and dock survive reopening', () async {
    final root = await Directory.systemTemp.createTemp('nala-toolbar-');
    addTearDown(() => root.delete(recursive: true));
    final prefs = await ToolbarPreferencesController.open(root.path);
    final order = [...prefs.layout.order];
    order.remove(ToolbarAction.latex);
    order.insert(0, ToolbarAction.latex);
    await prefs.update(
      ToolbarLayout(
        order: order,
        visible: {ToolbarAction.latex, ToolbarAction.pen, ToolbarAction.undo},
        dock: ToolbarDock.right,
      ),
    );
    final reopened = await ToolbarPreferencesController.open(root.path);
    expect(reopened.layout.dock, ToolbarDock.right);
    expect(reopened.layout.order.first, ToolbarAction.latex);
    expect(reopened.layout.visible, {
      ToolbarAction.latex,
      ToolbarAction.pen,
      ToolbarAction.undo,
    });
    prefs.dispose();
    reopened.dispose();
  });

  test(
    'invalid preferences recover defaults without breaking editor',
    () async {
      final root = await Directory.systemTemp.createTemp('nala-toolbar-bad-');
      addTearDown(() => root.delete(recursive: true));
      await File(
        '${root.path}/toolbar.json',
      ).writeAsString('{"version":1,"dock":"diagonal"}');
      final prefs = await ToolbarPreferencesController.open(root.path);
      expect(prefs.layout.dock, ToolbarDock.top);
      expect(prefs.layout.visible.contains(ToolbarAction.pen), isTrue);
      expect(prefs.layout.order.toSet().length, ToolbarAction.values.length);
      prefs.dispose();
    },
  );

  test('empty visible set persists and pending changes serialize', () async {
    final root = await Directory.systemTemp.createTemp('nala-toolbar-queue-');
    addTearDown(() => root.delete(recursive: true));
    final prefs = await ToolbarPreferencesController.open(root.path);
    final first = prefs.update(prefs.layout.copyWith(dock: ToolbarDock.left));
    final last = prefs.update(prefs.layout.copyWith(visible: {}));
    await Future.wait([first, last]);
    final reopened = await ToolbarPreferencesController.open(root.path);
    expect(reopened.layout.dock, ToolbarDock.left);
    expect(reopened.layout.visible, isEmpty);
    prefs.dispose();
    reopened.dispose();
  });
}
