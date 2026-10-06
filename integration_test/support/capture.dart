import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> captureUi(
  WidgetTester tester,
  Finder boundary,
  String name,
) async {
  await tester.pump();
  final image = await tester
      .renderObject<RenderRepaintBoundary>(boundary)
      .toImage();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('.dart_tool/ui-qa');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
