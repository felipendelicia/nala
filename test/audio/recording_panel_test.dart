import 'dart:io';

import 'package:apuntes/audio/notebook_audio_session.dart';
import 'package:apuntes/audio/recording_panel.dart';
import 'package:apuntes/document/notebook_recording.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/memory_repository.dart';
import 'notebook_audio_test.dart'
    show TimelineAudioDevice, RejectingAssets, pcmWav;

void main() {
  testWidgets(
    'storage failure keeps the panel open with working save retry and explicit discard',
    (tester) async {
      final fixture = (await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp(
          'nala-pending-panel-',
        );
        final assets = RejectingAssets();
        var revision = 0;
        final controller = EditorController(
          notebook: fixtureNotebook(),
          repository: MemoryRepository(),
          deviceId: 'test',
          newId: () => 'revision-${revision++}',
          now: DateTime.now,
        );
        final session = NotebookAudioSession(
          device: TimelineAudioDevice(),
          assets: assets,
          directory: root.path,
          controller: controller,
        );
        await session.start();
        await session.stop();
        return (
          root: root,
          assets: assets,
          controller: controller,
          session: session,
        );
      }))!;
      final root = fixture.root,
          assets = fixture.assets,
          controller = fixture.controller,
          session = fixture.session;
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordingPanel(
              session: session,
              controller: controller,
              onClose: () => closed = true,
            ),
          ),
        ),
      );
      expect(find.text('Reintentar guardar'), findsOneWidget);
      expect(find.text('Descartar grabación pendiente'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Cerrar audio'));
        while (session.busy) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pumpAndSettle();
      expect(closed, isFalse);
      expect(session.pendingSave, isTrue);
      assets.reject = false;
      await tester.runAsync(() async {
        await tester.tap(find.text('Reintentar guardar'));
        while (session.busy) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pumpAndSettle();
      expect(controller.notebook.recordings, hasLength(1));
      expect(session.pendingSave, isFalse);
      assets.reject = true;
      await tester.runAsync(() async {
        await session.start();
        await session.stop();
      });
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Eliminar grabación',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Renombrar grabación',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.runAsync(
        () => tester.tap(find.text('Descartar grabación pendiente')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Descartar grabación'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Descartar grabación'));
        while (session.busy) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pumpAndSettle();
      expect(session.pendingSave, isFalse);
      expect(controller.notebook.recordings, hasLength(1));
      await tester.tap(find.byTooltip('Cerrar audio'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      controller.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );

  testWidgets(
    'rename and delete recording preserve ink and clear audio links on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('nala-recording-panel-'),
      ))!;
      final assets = MemoryAssets();
      final repository = MemoryRepository();
      final recording = NotebookRecording(
        id: 'recording',
        title: 'Clase 1',
        assetId: await assets.put(pcmWav()),
        durationMs: 1000,
        createdAt: DateTime.utc(2026, 10, 7),
      );
      final notebook = fixtureNotebook();
      var id = 0;
      final controller = EditorController(
        notebook: notebook.copyWith(
          recordings: [recording],
          pages: [
            notebook.pages.single.copyWith(
              strokes: [
                fixtureStroke().copyWith(
                  audioRecordingId: recording.id,
                  audioOffsetMs: 250,
                ),
              ],
            ),
          ],
        ),
        repository: repository,
        deviceId: 'test',
        newId: () => 'revision-${id++}',
        now: DateTime.now,
      );
      final session = NotebookAudioSession(
        device: TimelineAudioDevice(),
        assets: assets,
        directory: root.path,
        controller: controller,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordingPanel(
              session: session,
              controller: controller,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Renombrar grabación'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre'),
        'Álgebra · vectores',
      );
      await tester.tap(find.text('Guardar nombre'));
      await tester.pumpAndSettle();
      expect(
        (await repository.load(notebook.id))!.recordings.single.title,
        'Álgebra · vectores',
      );
      await tester.tap(find.byTooltip('Eliminar grabación'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      final saved = (await repository.load(notebook.id))!;
      expect(saved.recordings, isEmpty);
      expect(saved.pages.single.strokes.single.points, hasLength(2));
      expect(saved.pages.single.strokes.single.audioRecordingId, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await session.suspend();
      session.dispose();
      controller.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
}
