import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/library/library_controller.dart';
import 'package:apuntes/workspace/document_workspace.dart';
import '../support/memory_repository.dart';

void main() {
  testWidgets('split editors retain independent controller and mounted state', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('nala-workspace-');
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MemoryRepository();
    final library = LibraryController(repository: repository, deviceId: 'pc');
    final first = await library.createNotebook(
      title: 'Primero',
      subject: '',
      pattern: PaperPattern.blank,
    );
    await library.createNotebook(
      title: 'Segundo',
      subject: '',
      pattern: PaperPattern.blank,
    );
    final services = AppServices(
      root: directory.path,
      deviceId: 'pc',
      repository: repository,
      assets: MemoryAssets(),
      library: library,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(services: services, initialEntry: first),
      ),
    );
    await tester.pumpAndSettle();
    final firstState = tester.state(find.byType(EditorScreen));
    await tester.tap(find.byTooltip('Abrir otro apunte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Segundo').last);
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Vista dividida'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNWidgets(2));
    final states = tester.stateList(find.byType(EditorScreen));
    expect(states.any((state) => identical(state, firstState)), isTrue);
    final editors = tester.widgetList<EditorScreen>(find.byType(EditorScreen));
    expect(editors.where((editor) => editor.active).length, 1);
    expect(editors.map((editor) => editor.controller.notebook.title).toSet(), {
      'Primero',
      'Segundo',
    });
    final inactive = editors.firstWhere((editor) => !editor.active);
    final sheet = find.descendant(
      of: find.byKey(
        ValueKey('workspace-editor-${inactive.controller.notebook.id}'),
      ),
      matching: find.byKey(const ValueKey('document-viewport')),
    );
    final pen = await tester.startGesture(
      tester.getCenter(sheet),
      kind: PointerDeviceKind.stylus,
    );
    await tester
        .pump(); // Apply active-pane update while its first pen stroke is down.
    await pen.moveBy(const Offset(30, 20));
    await pen.up();
    await tester.pumpAndSettle();
    expect(
      inactive.controller.notebook.pages.first.strokes,
      hasLength(1),
      reason: 'The first stroke must survive activation of an inactive pane.',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      inactive.controller.notebook.pages.first.strokes,
      isEmpty,
      reason:
          'Undo must target the active pane after the user touches its canvas.',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await services.close();
  });
}
