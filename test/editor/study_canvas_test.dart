import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import '../support/study_fixture.dart';

void main() {
  testWidgets('page text objects render in their document rectangle', (
    tester,
  ) async {
    final map = studyPayload();
    map['pages'][0]['objects'].removeAt(1);
    final page = NotebookCodec.decode(jsonEncode(map)).pages.single;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: PaperCanvas(
            page: page,
            tool: EditorTool.selection,
            onStroke: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Álgebra λ'), findsOneWidget);
    final origin = tester.getTopLeft(find.byType(PaperCanvas));
    expect(
      tester.getTopLeft(find.text('Álgebra λ')),
      origin + const Offset(50, 70),
    );
  });

  for (final pattern in ['cornell', 'weekly']) {
    testWidgets('$pattern paper has visible writing guides', (tester) async {
      final map = studyPayload();
      map['pages'][0]['objects'] = [];
      map['pages'][0]['strokes'] = [];
      map['pages'][0]['width'] = 300;
      map['pages'][0]['height'] = 420;
      map['pages'][0]['background'] = {'kind': 'paper', 'pattern': pattern};
      final page = NotebookCodec.decode(jsonEncode(map)).pages.single;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: PaperCanvas(
                page: page,
                tool: EditorTool.selection,
                onStroke: (_) {},
              ),
            ),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final pixels = (await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        } finally {
          image.dispose();
        }
      }))!;
      final distinct = <int>{};
      for (var at = 0; at < pixels.lengthInBytes; at += 4) {
        distinct.add(pixels.getUint32(at));
      }
      expect(distinct.length, greaterThan(1));
    });
  }
}
