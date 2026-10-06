import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> makeFixturePdf() async {
  final doc = pw.Document();
  for (final size in [(595.28, 841.89), (841.89, 595.28)]) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(size.$1, size.$2, marginAll: 0),
        build: (_) => pw.Stack(
          children: [
            pw.Positioned(
              left: 12,
              top: 12,
              child: pw.Container(
                width: 8,
                height: 8,
                color: const PdfColor(1, 0, 0),
              ),
            ),
            pw.Positioned(
              right: 12,
              bottom: 12,
              child: pw.Container(
                width: 8,
                height: 8,
                color: const PdfColor(0, 1, 0),
              ),
            ),
            pw.Positioned(
              left: 30,
              top: 50,
              child: pw.Text(
                'NALA PDF TEST',
                style: pw.TextStyle(font: pw.Font.helvetica(), fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}
