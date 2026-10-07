import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/page_object.dart';
import 'package:apuntes/elements/element_store.dart';

void main() {
  late Directory directory;
  late ElementStore store;
  final rendered = 'a' * 64, original = 'b' * 64, formula = 'c' * 64;
  NotebookPage selectionPage() => NotebookPage(
    id: 'source-page',
    width: 600,
    height: 800,
    background: const PageBackground.paper(PaperPattern.blank),
    strokes: [
      InkStroke(
        id: 'ink',
        tool: InkTool.pen,
        argb: 0xff202020,
        width: 2,
        audioRecordingId: 'recording',
        audioOffsetMs: 500,
        points: const [
          InkPoint(x: 100, y: 120, pressure: 1),
          InkPoint(x: 200, y: 140, pressure: .5),
        ],
      ),
    ],
    objects: [
      PageObject(
        id: 'text',
        kind: PageObjectKind.text,
        x: 80,
        y: 90,
        width: 140,
        height: 30,
        text: 'Una idea',
      ),
      PageObject(
        id: 'image',
        kind: PageObjectKind.image,
        x: 240,
        y: 90,
        width: 200,
        height: 180,
        assetId: rendered,
        originalAssetId: original,
        opacity: .4,
        locked: true,
      ),
      PageObject(
        id: 'formula',
        kind: PageObjectKind.latex,
        x: 80,
        y: 280,
        width: 140,
        height: 40,
        text: r'x^2',
        assetId: formula,
      ),
      PageObject(
        id: 'excluded',
        kind: PageObjectKind.text,
        x: 10,
        y: 10,
        width: 50,
        height: 20,
        text: 'No seleccionada',
      ),
    ],
  );
  const selection = {'ink', 'text', 'image', 'formula'};
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nala-elements-');
    store = ElementStore(root: directory.path);
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'saved selection reopens with names, normalized content and assets',
    () async {
      final saved = await store.saveSelection(
        name: '  Mi idea  ',
        page: selectionPage(),
        ids: selection,
      );
      final reopened = ElementStore(root: directory.path);
      final loaded = (await reopened.load()).single;
      expect(loaded.id, saved.id);
      expect(loaded.name, 'Mi idea');
      expect(loaded.width, 360);
      expect(loaded.height, 230);
      expect(loaded.strokes.single.points.first.x, 20);
      expect(loaded.strokes.single.points.first.y, 30);
      expect(loaded.strokes.single.audioRecordingId, isNull);
      expect(loaded.strokes.single.audioOffsetMs, isNull);
      expect(loaded.objects.map((o) => o.id), ['text', 'image', 'formula']);
      expect(loaded.objects.first.x, 0);
      expect(loaded.objects.first.y, 0);
      expect(loaded.objects.last.text, r'x^2');
      expect(loaded.assetIds, {rendered, original, formula});
      final json =
          jsonDecode(
                await File(
                  '${directory.path}/elements/registry.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(json['version'], 1);
      final image = (json['elements'][0]['objects'] as List)[1];
      expect(image['assetId'], rendered);
      expect(image['originalAssetId'], original);
    },
  );

  test(
    'insert creates unlocked copies fitted to the page with no audio refs',
    () async {
      final saved = await store.saveSelection(
        name: 'Grupo',
        page: selectionPage(),
        ids: selection,
      );
      final destination = NotebookPage(
        id: 'target',
        width: 180,
        height: 115,
        background: const PageBackground.paper(PaperPattern.blank),
      );
      var next = 0;
      final inserted = store.insert(
        saved,
        destination,
        const Offset(50, 80),
        newId: () => 'new-${next++}',
      );
      expect(inserted.strokes.single.id, 'new-0');
      expect(inserted.objects.map((o) => o.id), ['new-1', 'new-2', 'new-3']);
      expect(inserted.strokes.single.width, 1);
      expect(inserted.strokes.single.points.first.x, 10);
      expect(inserted.strokes.single.points.first.y, 15);
      expect(inserted.strokes.single.audioRecordingId, isNull);
      expect(inserted.strokes.single.audioOffsetMs, isNull);
      final image = inserted.objects[1];
      expect(image.x, 80);
      expect(image.y, 0);
      expect(image.width, 100);
      expect(image.height, 90);
      expect(image.locked, isFalse);
      expect(image.opacity, .4);
      expect(image.assetId, rendered);
      expect(image.originalAssetId, original);
      expect(inserted.objects.last.assetId, formula);
      expect(inserted.objects.last.text, r'x^2');
      expect(destination.objects, isEmpty);
    },
  );

  test(
    'insertion clamps the whole rotated group and preserves existing content',
    () async {
      final source = NotebookPage(
        id: 'source',
        width: 500,
        height: 500,
        background: const PageBackground.paper(PaperPattern.blank),
        objects: [
          PageObject(
            id: 'rotated',
            kind: PageObjectKind.text,
            x: 100,
            y: 100,
            width: 60,
            height: 20,
            rotation: 1.5707963267948966,
            text: 'Giro',
          ),
        ],
      );
      final element = await store.saveSelection(
        name: 'Giro',
        page: source,
        ids: {'rotated'},
      );
      final inserted = store.insert(
        element,
        source,
        const Offset(490, 490),
        newId: () => 'copy',
      );
      expect(inserted.objects.first.id, 'rotated');
      final copy = inserted.objects.last;
      expect(copy.x + copy.width / 2, closeTo(490, .001));
      expect(copy.y + copy.height / 2, closeTo(470, .001));
      expect(copy.rotation, closeTo(1.5707963267948966, .001));
    },
  );

  test(
    'different store instances serialize mutations and registry locks',
    () async {
      final other = ElementStore(root: directory.path);
      final elements = await Future.wait([
        store.saveSelection(name: 'Uno', page: selectionPage(), ids: {'text'}),
        other.saveSelection(name: 'Dos', page: selectionPage(), ids: {'ink'}),
      ]);
      await Future.wait([
        store.rename(elements.first.id, 'Título nuevo'),
        other.remove(elements.last.id),
      ]);
      expect((await other.load()).single.name, 'Título nuevo');
      expect((await store.load(query: 'TÍTULO')).single.id, elements.first.id);
      await ElementStore.withRegistryLock(directory.path, () async {
        final raw = await File(
          '${directory.path}/elements/registry.json',
        ).readAsString();
        expect(ElementStore.validateRegistry(raw).single.id, elements.first.id);
      });
    },
  );

  test('invalid names and empty selection do not alter the registry', () async {
    final saved = await store.saveSelection(
      name: 'Válido',
      page: selectionPage(),
      ids: {'text'},
    );
    await expectLater(
      store.saveSelection(
        name: 'Vacío',
        page: selectionPage(),
        ids: {'missing'},
      ),
      throwsFormatException,
    );
    await expectLater(store.rename(saved.id, '   '), throwsFormatException);
    await expectLater(
      store.saveSelection(
        name: 'x' * 121,
        page: selectionPage(),
        ids: {'text'},
      ),
      throwsFormatException,
    );
    expect((await store.load()).single.name, 'Válido');
  });

  test(
    'corrupt, duplicate and inconsistent registry content is rejected',
    () async {
      final saved = await store.saveSelection(
        name: 'Válido',
        page: selectionPage(),
        ids: {'text'},
      );
      final value = saved.toJson();
      for (final raw in [
        '{',
        jsonEncode({
          'version': 2,
          'elements': [value],
        }),
        jsonEncode({
          'version': 1,
          'elements': [value, value],
        }),
        jsonEncode({
          'version': 1,
          'elements': [
            {...value, 'width': -1},
          ],
        }),
        jsonEncode({
          'version': 1,
          'elements': [
            {...value, 'width': 1},
          ],
        }),
      ]) {
        expect(() => ElementStore.validateRegistry(raw), throwsFormatException);
      }
    },
  );
}
