import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/revision.dart';
import '../support/fixtures.dart';

void main() {
  test('el codec conserva presión, patrón y coordenadas', () {
    final restored = NotebookCodec.decode(NotebookCodec.encode(fixtureNotebook()));
    expect(restored.pages.single.background.pattern, PaperPattern.grid);
    expect(restored.pages.single.strokes.single.points.last.pressure, .75);
    expect(restored.pages.single.strokes.single.points.last.x, 30);
    expect(restored.pages.single.width, 595.28);
    expect(restored.title, 'Álgebra');
  });
  test('cambiar el patrón conserva los trazos', () {
    final page = fixtureNotebook().pages.single;
    final changed = page.copyWith(background: PageBackground.paper(PaperPattern.ruled));
    expect(changed.strokes.single.points.last.x, 30);
    expect(changed.strokes.single.id, 'stroke-1');
  });
  test('las colecciones no permiten modificar el documento original', () {
    expect(() => fixtureNotebook().pages.clear(), throwsUnsupportedError);
    expect(() => fixtureStroke().points.clear(), throwsUnsupportedError);
  });
  test('el codec conserva un fondo PDF y una revisión con su padre', () {
    final notebook = fixtureNotebook();
    final pdf = notebook.copyWith(pages: [notebook.pages.single.copyWith(
      background: PageBackground.pdf('a' * 64, 2))]);
    final revision = Revision(id: 'r2', deviceId: 'tablet', parentId: 'r1',
      createdAt: DateTime.utc(2026), notebook: pdf);
    final decoded = NotebookCodec.decodeRevision(NotebookCodec.encodeRevision(revision));
    expect(decoded.parentId, 'r1');
    expect(decoded.notebook.pages.single.background.pageNumber, 2);
    expect(decoded.notebook.pages.single.background.assetId, 'a' * 64);
  });
  test('rechaza una versión futura y páginas duplicadas', () {
    final payload = jsonDecode(NotebookCodec.encode(fixtureNotebook())) as Map<String, dynamic>;
    payload['schemaVersion'] = 99;
    expect(() => NotebookCodec.decode(jsonEncode(payload)), throwsFormatException);
    payload['schemaVersion'] = 1;
    payload['pages'] = [payload['pages'][0], payload['pages'][0]];
    expect(() => NotebookCodec.decode(jsonEncode(payload)), throwsFormatException);
  });
  test('rechaza tamaño inválido y una variante ambigua de fondo', () {
    final payload = jsonDecode(NotebookCodec.encode(fixtureNotebook())) as Map<String, dynamic>;
    payload['pages'][0]['width'] = 0;
    expect(() => NotebookCodec.decode(jsonEncode(payload)), throwsFormatException);
    payload['pages'][0]['width'] = 595.28;
    payload['pages'][0]['background']['assetId'] = 'a' * 64;
    expect(() => NotebookCodec.decode(jsonEncode(payload)), throwsFormatException);
  });
}
