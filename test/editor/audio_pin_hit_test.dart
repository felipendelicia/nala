import 'package:apuntes/audio/audio_service.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_recording.dart';
import 'package:apuntes/document/page_comment.dart';
import 'package:apuntes/editor/comment_dialog.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

class _NoMicrophone implements AudioDevice {
  @override
  Future<void> start(String path) async =>
      throw StateError('Unexpected capture');
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<void> play(String path) async =>
      throw StateError('Unexpected playback');
  @override
  Future<void> stopPlayback() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('reading opens a visible comment pin above linked audio ink', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final original = fixtureNotebook();
    final controller = EditorController(
      notebook: original.copyWith(
        recordings: [
          NotebookRecording(
            id: 'class-audio',
            title: 'Clase',
            assetId: 'a' * 64,
            durationMs: 1000,
            createdAt: DateTime.utc(2026),
          ),
        ],
        pages: [
          original.pages.single.copyWith(
            comments: [
              PageComment(
                id: 'comment',
                x: 120,
                y: 120,
                text: 'Consultar el teorema',
                createdAt: DateTime.utc(2026),
              ),
            ],
            strokes: [
              fixtureStroke().copyWith(
                points: [
                  const InkPoint(x: 100, y: 120, pressure: 1),
                  const InkPoint(x: 200, y: 120, pressure: 1),
                ],
                audioRecordingId: 'class-audio',
                audioOffsetMs: 0,
              ),
            ],
          ),
        ],
      ),
      repository: MemoryRepository(),
      deviceId: 'test',
      newId: () => 'revision',
      now: () => DateTime.utc(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EditorScreen(
          controller: controller,
          assets: MemoryAssets(),
          audio: _NoMicrophone(),
          audioDirectory: '/unused',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Modo lectura'));
    await tester.pumpAndSettle();
    final box = tester.renderObject<RenderBox>(find.byType(PaperCanvas));
    await tester.tapAt(box.localToGlobal(const Offset(120, 120)));
    await tester.pumpAndSettle();
    expect(find.byType(CommentDialog), findsOneWidget);
    expect(find.text('Consultar el teorema'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
