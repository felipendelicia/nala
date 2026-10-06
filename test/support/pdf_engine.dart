import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> initializePdfForTest(String directory) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_tester has no app bundle lib/ directory. Use the actual PDFium
  // native asset produced by the Linux build, without mocking the engine.
  final library = File('build/native_assets/linux/libpdfium.so');
  if (!await library.exists()) {
    throw StateError(
      'Build Linux first to provide the PDFium native test library.',
    );
  }
  Pdfrx.pdfiumModulePath ??= library.absolute.path;
  await pdfrxInitialize(tmpPath: directory);
}
