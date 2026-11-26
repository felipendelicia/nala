import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/revision.dart';
import '../support/fixtures.dart';

void main() {
  test('el codec conserva presión, patrón y coordenadas', () {
    final restored = NotebookCodec.decode(
      NotebookCodec.encode(fixtureNotebook()),
    );
    expect(restored.pages.single.background.pattern, PaperPattern.grid);
    expect(restored.pages.single.strokes.single.points.last.pressure, .75);
    expect(restored.pages.single.strokes.single.points.last.x, 30);
    expect(restored.pages.single.width, 595.28);
    expect(restored.title, 'Álgebra');
  });
  test('el codec restaura coordenadas antiguas y escribe x e y', () {
    final revision = Revision(
      id: 'revision-de-tinta',
      deviceId: 'tablet',
      parentId: null,
      createdAt: DateTime.utc(2026),
      notebook: fixtureNotebook(),
    );
    final payload = jsonDecode(NotebookCodec.encodeRevision(revision));
    final points = payload['notebook']['pages'][0]['strokes'][0]['points'];
    points[0] = {'-': 10.25, 'y': 20, 'pressure': .25};
    points[1] = {'x': 30, '-': 40.5, 'pressure': .75};

    final decoded = NotebookCodec.decodeRevision(jsonEncode(payload));
    final encoded = jsonDecode(NotebookCodec.encodeRevision(decoded));
    expect(encoded['notebook']['pages'][0]['strokes'][0]['points'], [
      {'x': 10.25, 'y': 20, 'pressure': .25},
      {'x': 30, 'y': 40.5, 'pressure': .75},
    ]);
  });
  test('la variante antigua no admite puntos inválidos ni claves extra', () {
    final invalid = <Map<String, Object?>>[
      {'-': 10, 'pressure': .25},
      {'-': 10, 'other': 20, 'pressure': .25},
      {'x': null, '-': 20, 'pressure': .25},
      {'x': 10, 'y': null, '-': 20, 'pressure': .25},
      {'x': 10, '-': double.nan, 'pressure': .25},
      {'-': double.infinity, 'y': 20, 'pressure': .25},
      {'x': 10, '-': 20, 'pressure': 1.1},
      {'x': 10, '-': 20},
      {'x': 10, '-': 20, 'pressure': .25, 'extra': true},
    ];
    for (final point in invalid) {
      expect(() => InkPoint.fromJson(point), throwsFormatException);
    }
  });
  test('cambiar el patrón conserva los trazos', () {
    final page = fixtureNotebook().pages.single;
    final changed = page.copyWith(
      background: PageBackground.paper(PaperPattern.ruled),
    );
    expect(changed.strokes.single.points.last.x, 30);
    expect(changed.strokes.single.id, 'stroke-1');
  });
  test('las colecciones no permiten modificar el documento original', () {
    expect(() => fixtureNotebook().pages.clear(), throwsUnsupportedError);
    expect(() => fixtureStroke().points.clear(), throwsUnsupportedError);
  });
  test(
    'el codec conserva las transcripciones guardadas por versiones anteriores',
    () {
      final notebook = fixtureNotebook();
      expect(
        NotebookCodec.decode(NotebookCodec.encode(notebook)).transcriptions,
        isEmpty,
      );
      final payload =
          jsonDecode(NotebookCodec.encode(notebook)) as Map<String, dynamic>;
      final legacy = {
        'id': 'clase-1',
        'createdAt': '2026-11-25T14:00:00.000Z',
        'text': 'Álgebra lineal.\nUn espacio vectorial…',
        'cleanedText': 'Álgebra lineal.\nUn espacio vectorial.',
        'summary': 'Espacios vectoriales.',
      };
      payload['transcriptions'] = [legacy];
      final restored = NotebookCodec.decode(jsonEncode(payload));
      expect(jsonDecode(NotebookCodec.encode(restored))['transcriptions'], [
        legacy,
      ]);
    },
  );
  test('el codec rechaza transcripciones duplicadas', () {
    final payload =
        jsonDecode(NotebookCodec.encode(fixtureNotebook()))
            as Map<String, dynamic>;
    final transcript = {
      'id': 'clase-1',
      'createdAt': '2026-11-25T14:00:00.000Z',
      'text': 'Álgebra lineal.',
    };
    payload['transcriptions'] = [transcript, transcript];
    expect(
      () => NotebookCodec.decode(jsonEncode(payload)),
      throwsFormatException,
    );
  });
  test('el codec conserva un fondo PDF y una revisión con su padre', () {
    final notebook = fixtureNotebook();
    final pdf = notebook.copyWith(
      pages: [
        notebook.pages.single.copyWith(
          background: PageBackground.pdf('a' * 64, 2),
        ),
      ],
    );
    final revision = Revision(
      id: 'r2',
      deviceId: 'tablet',
      parentId: 'r1',
      createdAt: DateTime.utc(2026),
      notebook: pdf,
    );
    final decoded = NotebookCodec.decodeRevision(
      NotebookCodec.encodeRevision(revision),
    );
    expect(decoded.parentId, 'r1');
    expect(decoded.notebook.pages.single.background.pageNumber, 2);
    expect(decoded.notebook.pages.single.background.assetId, 'a' * 64);
  });
  test('rechaza una versión futura y páginas duplicadas', () {
    final payload =
        jsonDecode(NotebookCodec.encode(fixtureNotebook()))
            as Map<String, dynamic>;
    payload['schemaVersion'] = 99;
    expect(
      () => NotebookCodec.decode(jsonEncode(payload)),
      throwsFormatException,
    );
    payload['schemaVersion'] = 1;
    payload['pages'] = [payload['pages'][0], payload['pages'][0]];
    expect(
      () => NotebookCodec.decode(jsonEncode(payload)),
      throwsFormatException,
    );
  });
  test('rechaza tamaño inválido y una variante ambigua de fondo', () {
    final payload =
        jsonDecode(NotebookCodec.encode(fixtureNotebook()))
            as Map<String, dynamic>;
    payload['pages'][0]['width'] = 0;
    expect(
      () => NotebookCodec.decode(jsonEncode(payload)),
      throwsFormatException,
    );
    payload['pages'][0]['width'] = 595.28;
    payload['pages'][0]['background']['assetId'] = 'a' * 64;
    expect(
      () => NotebookCodec.decode(jsonEncode(payload)),
      throwsFormatException,
    );
  });
}
