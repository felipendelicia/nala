import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:apuntes/editor/editor_toolbar.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:apuntes/editor/pen_preferences.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

Future<void> nativeEdge(WidgetTester tester, String method, [bool? value]) {
  final done = Completer<void>();
  tester.binding.channelBuffers.push(
    'nala/stylus',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, value)),
    (_) => done.complete(),
  );
  return done.future;
}

Future<EditorController> editor(
  WidgetTester tester, {
  PenPreferencesController? prefs,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  var id = 0;
  final c = EditorController(
    notebook: fixtureNotebook(),
    repository: MemoryRepository(),
    deviceId: 'pc',
    newId: () => 'r${++id}',
    now: () => DateTime.utc(2026),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: EditorScreen(controller: c, penPreferences: prefs),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() {
    c.dispose();
  });
  return c;
}

EditorTool selectedTool(WidgetTester tester) =>
    tester.widget<EditorToolbar>(find.byType(EditorToolbar)).tool;

void main() {
  test('ajustes sobreviven reinicio y recuperan archivos dañados', () async {
    final dir = await Directory.systemTemp.createTemp('nala-pen-');
    try {
      final prefs = await PenPreferencesController.open(dir.path);
      await prefs.update(
        const PenSettings(
          pressure: .6,
          stabilization: .12,
          buttonTool: PenButtonTool.highlighter,
          buttonMode: PenButtonMode.toggle,
        ),
      );
      final reopened = await PenPreferencesController.open(dir.path);
      expect(reopened.value.pressure, .6);
      expect(reopened.value.stabilization, .12);
      expect(reopened.value.buttonTool, PenButtonTool.highlighter);
      expect(reopened.value.buttonMode, PenButtonMode.toggle);
      await File('${dir.path}/pen.json').writeAsString(
        jsonEncode({
          'pressure': -20,
          'stabilization': 'bad',
          'buttonTool': 'invalid',
          'buttonMode': [],
        }),
      );
      final invalid = await PenPreferencesController.open(dir.path);
      expect(invalid.value.pressure, 1);
      expect(invalid.value.stabilization, 0);
      expect(invalid.value.buttonTool, PenButtonTool.eraser);
      await File('${dir.path}/pen.json').writeAsString('{');
      expect(
        (await PenPreferencesController.open(dir.path)).value.buttonMode,
        PenButtonMode.hold,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
  testWidgets(
    'botón nativo en hover, levantar punta no lo suelta y cancelar restaura',
    (tester) async {
      final c = await editor(tester);
      final center = tester.getCenter(find.byType(PaperCanvas));
      await nativeEdge(tester, 'button', true);
      await tester.pump();
      expect(selectedTool(tester), EditorTool.eraser);
      final pen = await tester.startGesture(
        center,
        kind: PointerDeviceKind.stylus,
        buttons: kPrimaryStylusButton,
        pointer: 13,
      );
      await pen.moveBy(const Offset(10, 0));
      await pen.up();
      await tester.pump();
      expect(
        selectedTool(tester),
        EditorTool.eraser,
        reason: 'UP sin botón en Flutter no es una liberación física.',
      );
      await nativeEdge(tester, 'button', false);
      await tester.pump();
      expect(selectedTool(tester), EditorTool.pen);
      await nativeEdge(tester, 'button', true);
      await tester.pump();
      final contact = await tester.startGesture(
        center,
        kind: PointerDeviceKind.stylus,
        buttons: kPrimaryStylusButton,
        pointer: 14,
      );
      await contact.cancel();
      await tester.pump();
      expect(selectedTool(tester), EditorTool.pen);
      expect(c.notebook.pages.first.strokes, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'lectura y modal bloquean botón; perder foco restaura herramienta',
    (tester) async {
      final c = await editor(tester);
      await tester.tap(find.byTooltip('Modo lectura'));
      await tester.pumpAndSettle();
      await nativeEdge(tester, 'button', true);
      final pen = await tester.startGesture(
        tester.getCenter(find.byType(PaperCanvas)),
        kind: PointerDeviceKind.stylus,
        buttons: kPrimaryStylusButton,
      );
      await pen.moveBy(const Offset(10, 10));
      await pen.up();
      await tester.pumpAndSettle();
      expect(c.notebook.pages.first.strokes, hasLength(1));
      await tester.tap(find.byTooltip('Modo editor'));
      await tester.pumpAndSettle();
      expect(selectedTool(tester), EditorTool.pen);
      await tester.tap(find.byTooltip('Ajustes del lápiz'));
      await tester.pumpAndSettle();
      await nativeEdge(tester, 'button', true);
      await tester.pump();
      expect(selectedTool(tester), EditorTool.pen);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await nativeEdge(tester, 'button', true);
      await tester.pump();
      expect(selectedTool(tester), EditorTool.eraser);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(selectedTool(tester), EditorTool.pen);
      await nativeEdge(tester, 'button', true);
      await tester.pump();
      expect(
        selectedTool(tester),
        EditorTool.pen,
        reason: 'Eventos pendientes en segundo plano no activan herramientas.',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('botón derecho de mouse y palma no cambian herramienta', (
    tester,
  ) async {
    await editor(tester);
    final center = tester.getCenter(find.byType(PaperCanvas));
    await tester.sendEventToBinding(
      PointerHoverEvent(
        kind: PointerDeviceKind.mouse,
        position: center,
        buttons: kSecondaryButton,
      ),
    );
    final touch = await tester.startGesture(
      center,
      kind: PointerDeviceKind.touch,
    );
    await touch.moveBy(const Offset(10, 0));
    await touch.up();
    await tester.pump();
    expect(selectedTool(tester), EditorTool.pen);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('canal Android evita que una muestra vieja suelte el botón', (
    tester,
  ) async {
    const channel = MethodChannel('nala/stylus');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await editor(tester);
    final center = tester.getCenter(find.byType(PaperCanvas));
    final pen = await tester.startGesture(
      center,
      kind: PointerDeviceKind.stylus,
      pointer: 15,
    );
    await pen.moveBy(const Offset(10, 0));
    await nativeEdge(tester, 'button', true);
    await tester.pump();
    expect(selectedTool(tester), EditorTool.eraser);
    // Android's channel edge and engine packet use separate queues. A packet
    // already in flight must not undo the authoritative hardware edge.
    await tester.sendEventToBinding(
      PointerMoveEvent(
        pointer: 15,
        kind: PointerDeviceKind.stylus,
        position: center + const Offset(20, 0),
        buttons: kPrimaryButton,
      ),
    );
    await tester.pump();
    expect(selectedTool(tester), EditorTool.eraser);
    await pen.up();
    await nativeEdge(tester, 'button', false);
    await tester.pump();
    expect(selectedTool(tester), EditorTool.pen);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'selección con botón se conserva al soltar para poder eliminarla',
    (tester) async {
      late Directory dir;
      late PenPreferencesController prefs;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('nala-selection-button-');
        prefs = await PenPreferencesController.open(dir.path);
        await prefs.update(
          const PenSettings(buttonTool: PenButtonTool.selection),
        );
      });
      final c = await editor(tester, prefs: prefs);
      final sheet = tester.renderObject<RenderBox>(find.byType(PaperCanvas));
      await nativeEdge(tester, 'button', true);
      await tester.pump();
      final pen = await tester.startGesture(
        sheet.localToGlobal(const Offset(3, 12)),
        kind: PointerDeviceKind.stylus,
        buttons: kPrimaryStylusButton,
      );
      await pen.moveTo(sheet.localToGlobal(const Offset(38, 48)));
      await pen.up();
      await tester.pump();
      expect(find.byTooltip('Eliminar selección'), findsOneWidget);
      await nativeEdge(tester, 'button', false);
      await tester.pump();
      expect(selectedTool(tester), EditorTool.pen);
      expect(find.byTooltip('Eliminar selección'), findsOneWidget);
      await tester.tap(find.byTooltip('Eliminar selección'));
      await tester.pumpAndSettle();
      expect(c.notebook.pages.first.strokes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
  for (final toggle in [false, true]) {
    testWidgets(
      toggle
          ? 'botón alterna resaltador y lápiz sin perder segmentos'
          : 'mantener botón usa goma y soltar recupera lápiz',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        late Directory dir;
        late PenPreferencesController prefs;
        await tester.runAsync(() async {
          dir = await Directory.systemTemp.createTemp('nala-button-');
          prefs = await PenPreferencesController.open(dir.path);
          if (toggle) {
            await prefs.update(
              const PenSettings(
                buttonTool: PenButtonTool.highlighter,
                buttonMode: PenButtonMode.toggle,
              ),
            );
          }
        });
        var id = 0;
        final controller = EditorController(
          notebook: fixtureNotebook(),
          repository: MemoryRepository(),
          deviceId: 'pc',
          newId: () => 'r${++id}',
          now: () => DateTime.utc(2026),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: EditorScreen(controller: controller, penPreferences: prefs),
          ),
        );
        await tester.pumpAndSettle();
        final center = tester.getCenter(find.byType(PaperCanvas));
        final pen = await tester.startGesture(
          center,
          kind: PointerDeviceKind.stylus,
          pointer: 6,
        );
        await pen.moveBy(const Offset(10, 0));
        // Change the side button during contact. Previous ink must be committed.
        await tester.sendEventToBinding(
          PointerMoveEvent(
            pointer: 6,
            kind: PointerDeviceKind.stylus,
            position: center + const Offset(20, 0),
            buttons: kPrimaryButton | kPrimaryStylusButton,
            pressure: .8,
          ),
        );
        await tester.pump();
        expect(controller.notebook.pages.first.strokes, hasLength(2));
        await tester.sendEventToBinding(
          PointerMoveEvent(
            pointer: 6,
            kind: PointerDeviceKind.stylus,
            position: center + const Offset(30, 0),
            buttons: kPrimaryButton,
            pressure: .8,
          ),
        );
        await pen.moveTo(center + const Offset(40, 0));
        await pen.up();
        await tester.pumpAndSettle();
        if (toggle) {
          expect(
            controller.notebook.pages.first.strokes.last.tool,
            InkTool.highlighter,
          );
          await tester.sendEventToBinding(
            PointerHoverEvent(
              kind: PointerDeviceKind.stylus,
              position: center,
              buttons: kPrimaryStylusButton,
            ),
          );
          await tester.sendEventToBinding(
            PointerHoverEvent(
              kind: PointerDeviceKind.stylus,
              position: center,
              buttons: 0,
            ),
          );
        }
        final after = await tester.startGesture(
          center + const Offset(80, 40),
          kind: PointerDeviceKind.stylus,
        );
        await after.moveBy(const Offset(20, 0));
        await after.up();
        await tester.pumpAndSettle();
        expect(controller.notebook.pages.first.strokes.last.tool, InkTool.pen);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await tester.runAsync(() => dir.delete(recursive: true));
      },
    );
  }
}
