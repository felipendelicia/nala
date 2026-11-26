import 'dart:convert';
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
        quickColors: [0xff24584b, 0xffe9ba3b],
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
    expect(reopened.layout.quickColors, [0xff24584b, 0xffe9ba3b]);
    prefs.dispose();
    reopened.dispose();
  });

  test(
    'a saved toolbar without quick colors keeps its customization',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'nala-toolbar-legacy-',
      );
      addTearDown(() => root.delete(recursive: true));
      final saved =
          ToolbarLayout.defaults()
              .copyWith(dock: ToolbarDock.left, visible: {ToolbarAction.color})
              .toJson()
            ..remove('quickColors');
      await File('${root.path}/toolbar.json').writeAsString(jsonEncode(saved));
      final prefs = await ToolbarPreferencesController.open(root.path);
      addTearDown(prefs.dispose);
      expect(prefs.layout.dock, ToolbarDock.left);
      expect(prefs.layout.visible, {ToolbarAction.color});
      expect(prefs.layout.quickColors, [0xff202020, 0xff284cad, 0xffc14747]);
    },
  );

  test(
    'quick colors retain their order and cap at three distinct palette colors',
    () {
      final layout = ToolbarLayout.defaults().copyWith(
        quickColors: [
          0xff24584b,
          0xff24584b,
          0xffff0000,
          0xffe9ba3b,
          0xff8553aa,
          0xff284cad,
        ],
      );
      expect(layout.quickColors, [0xff24584b, 0xffe9ba3b, 0xff8553aa]);
      final empty = layout.copyWith(quickColors: []);
      expect(ToolbarLayout.fromJson(empty.toJson()).quickColors, isEmpty);
    },
  );

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
