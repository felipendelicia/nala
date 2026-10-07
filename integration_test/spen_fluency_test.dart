import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:apuntes/app.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/editor/draft_ink.dart';
import 'package:apuntes/editor/pen_preferences.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/library/library_screen.dart';
import 'support/capture.dart';

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  final timer = Stopwatch()..start();
  while (!ready()) {
    if (timer.elapsed.inSeconds > 40) fail('Operación no terminó.');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Future<int> rasterFrame(DraftInk ink, bool incremental) async {
  final watch = Stopwatch()..start();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (incremental) {
    ink.paint(canvas);
  } else {
    canvas.drawPath(ink.path, Paint()..color = ink.color);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(600, 600);
  // Force pixels ready; elapsed includes real raster work, not just submission.
  await image.toByteData();
  image.dispose();
  picture.dispose();
  return watch.elapsedMicroseconds;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'trazo largo nativo, botón configurable y reinicio de preferencias',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('nala-spen-native-');
      final services = await AppServices.open(root.path);
      final note = Notebook.blank(
        id: 'pen-note',
        pageId: 'p0',
        title: 'S Pen',
        subject: 'Universidad',
        pattern: PaperPattern.blank,
        now: DateTime.now(),
      );
      await services.library.add(note);
      const preview = ValueKey('spen-preview');
      await tester.pumpWidget(
        RepaintBoundary(
          key: preview,
          child: NalaApp(services: services),
        ),
      );
      await waitFor(
        tester,
        () => find.byType(LibraryScreen).evaluate().isNotEmpty,
      );
      await tester.tap(find.text('S Pen'));
      await waitFor(
        tester,
        () => find.byType(EditorScreen).evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Ajustes del lápiz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Goma'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resaltador').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mantener apretado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pulsar para alternar').last);
      await tester.pumpAndSettle();
      await captureUi(tester, find.byKey(preview), 'spen-settings-v04');
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      await waitFor(
        tester,
        () =>
            services.penPreferences!.value.buttonTool ==
            PenButtonTool.highlighter,
      );
      final sheet = tester.renderObject<RenderBox>(
        find.byType(PaperCanvas).first,
      );
      final start = sheet.localToGlobal(const Offset(100, 180));
      final pen = await tester.startGesture(
        start,
        kind: PointerDeviceKind.stylus,
        pointer: 9,
      );
      for (var i = 1; i <= 360; i++) {
        await tester.sendEventToBinding(
          PointerMoveEvent(
            pointer: 9,
            kind: PointerDeviceKind.stylus,
            position: sheet.localToGlobal(
              Offset(100 + i * .7, 180 + math.sin(i * .08) * 18),
            ),
            pressure: .1 + .9 * (i % 80) / 80,
            pressureMin: 0,
            pressureMax: 1,
            buttons: kPrimaryButton,
          ),
        );
        if (i % 12 == 0) await tester.pump();
      }
      await pen.moveTo(sheet.localToGlobal(const Offset(352, 180)));
      await pen.up();
      await tester.pumpAndSettle();
      await captureUi(tester, find.byKey(preview), 'spen-ink-v04');
      await tester.tap(find.byTooltip('Volver a mis apuntes'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await services.close();
      final reopened = await AppServices.open(root.path);
      expect(
        reopened.penPreferences!.value.buttonTool,
        PenButtonTool.highlighter,
      );
      expect(reopened.penPreferences!.value.buttonMode, PenButtonMode.toggle);
      final stored = (await reopened.repository.list())
          .single
          .notebook
          .pages
          .first
          .strokes
          .single;
      expect(stored.points.length, greaterThan(350));
      expect(
        stored.points.map((p) => p.pressure).reduce(math.min),
        lessThan(.2),
      );
      expect(
        stored.points.map((p) => p.pressure).reduce(math.max),
        greaterThan(.9),
      );
      await reopened.close();
      await root.delete(recursive: true);

      final ink = DraftInk();
      ink.begin(
        const InkPoint(x: 20, y: 300, pressure: .5),
        tool: InkTool.pen,
        argb: 0xff000000,
        width: 2.5,
        rasterBounds: const Rect.fromLTWH(0, 0, 600, 600),
        stabilization: 0,
      );
      InkPoint point(int i) => InkPoint(
        x: 20 + (i % 560).toDouble(),
        y: 300 + math.sin(i * .08) * 100,
        pressure: .5 + .4 * math.sin(i * .05),
      );
      for (var i = 1; i <= 8000; i++) {
        ink.add(point(i));
      }
      await rasterFrame(ink, true);
      await rasterFrame(ink, false);
      final tiled = <int>[], vector = <int>[];
      for (var frame = 0; frame < 48; frame++) {
        for (var j = 0; j < 8; j++) {
          ink.add(point(8001 + frame * 8 + j));
        }
        // Alternate measurement order to reduce cache/warmup bias.
        if (frame.isEven) {
          tiled.add(await rasterFrame(ink, true));
          vector.add(await rasterFrame(ink, false));
        } else {
          vector.add(await rasterFrame(ink, false));
          tiled.add(await rasterFrame(ink, true));
        }
      }
      tiled.sort();
      vector.sort();
      final report = {
        'platform': 'Linux GTK; native debug renderer; synthetic stylus',
        'initial_samples': 8000,
        'frames': 48,
        'samples_per_frame': 8,
        'output_pixels': [600, 600],
        'incremental_median_us': tiled[24],
        'incremental_p95_us': tiled[45],
        'full_vector_median_us': vector[24],
        'full_vector_p95_us': vector[45],
        'measures':
            'offscreen raster + pixel readback; NOT physical pen-to-screen latency',
      };
      final output = File('.dart_tool/spen-raster-benchmark.json');
      await output.parent.create(recursive: true);
      await output.writeAsString(jsonEncode(report));
      debugPrint('NALA_RASTER_BENCH ${jsonEncode(report)}');
      expect(ink.finish('bench')!.points, hasLength(8385));
      ink.dispose();
    },
  );
}
