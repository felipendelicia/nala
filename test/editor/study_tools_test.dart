import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/page_object.dart';
import 'package:apuntes/editor/shape_tools.dart';
import 'package:apuntes/editor/selection_operations.dart';
import 'package:apuntes/editor/pen_favorites.dart';

void main() {
  test('perfect shapes remain vector ink with uniform pressure', () {
    final s = ShapeTools.stroke(
      ShapeKind.rectangle,
      const Offset(90, 80),
      const Offset(10, 20),
      id: 'shape',
      argb: 0xff123456,
      width: 3,
    );
    expect(s.points.first.x, 10);
    expect(s.points.first.y, 20);
    expect(s.points.last.x, s.points.first.x);
    expect(s.pressureCurve, PressureCurve.uniform);
    final ellipse = ShapeTools.stroke(
      ShapeKind.ellipse,
      Offset.zero,
      const Offset(100, 60),
      id: 'ellipse',
      argb: 0xff000000,
      width: 2,
    );
    expect(ellipse.points.map((p) => p.x).reduce((a, b) => a > b ? a : b), 100);
    expect(ShapeTools.recognize(ellipse), isNotNull);
  });
  test('recognition straightens a line but leaves writing untouched', () {
    InkStroke ink(List<InkPoint> p) => InkStroke(
      id: 's',
      tool: InkTool.pen,
      argb: 0xff000000,
      width: 2,
      points: p,
    );
    final line = ink([
      const InkPoint(x: 10, y: 10, pressure: 1),
      const InkPoint(x: 50, y: 10.5, pressure: 1),
      const InkPoint(x: 100, y: 10, pressure: 1),
    ]);
    expect(ShapeTools.recognize(line)!.points.every((p) => p.y == 10), isTrue);
    final scribble = ink([
      const InkPoint(x: 0, y: 0, pressure: 1),
      const InkPoint(x: 80, y: 20, pressure: 1),
      const InkPoint(x: 10, y: 60, pressure: 1),
      const InkPoint(x: 70, y: 100, pressure: 1),
    ]);
    expect(ShapeTools.recognize(scribble), isNull);
  });
  test('ruler projection constrains ink to its chosen angle', () {
    final p = ShapeTools.project(const Offset(20, 30), const Offset(80, 70), 0);
    expect(p, const Offset(80, 30));
    final vertical = ShapeTools.project(Offset.zero, const Offset(40, 50), 90);
    expect(vertical.dx, closeTo(0, .0001));
    expect(vertical.dy, closeTo(50, .0001));
  });
  test(
    'clipboard duplicates IDs, media and relative positions across sheets',
    () {
      var id = 0;
      final image = PageObject(
        id: 'image',
        kind: PageObjectKind.image,
        x: 50,
        y: 40,
        width: 60,
        height: 50,
        assetId: 'a' * 64,
      );
      final p = NotebookPage(
        id: 'page',
        width: 595,
        height: 842,
        background: const PageBackground.paper(PaperPattern.blank),
        objects: [image],
        strokes: [
          InkStroke(
            id: 's',
            tool: InkTool.pen,
            argb: 0xff000000,
            width: 2,
            points: [
              const InkPoint(x: 20, y: 30, pressure: 1),
              const InkPoint(x: 40, y: 30, pressure: 1),
            ],
          ),
        ],
      );
      final clip = SelectionClipboard()..capture(p, {'s', 'image'});
      final target = p.copyWith(strokes: [], objects: []);
      final first = clip.paste(
        target,
        const Offset(100, 100),
        newId: () => 'new-${id++}',
      );
      final second = clip.paste(
        first,
        const Offset(150, 150),
        newId: () => 'new-${id++}',
      );
      expect(second.strokes.map((s) => s.id).toSet().length, 2);
      expect(second.objects.map((o) => o.id).toSet().length, 2);
      expect(second.objects.first.assetId, image.assetId);
      expect(second.objects.first.x - second.strokes.first.points.first.x, 30);
      expect(p.strokes.single.id, 's');
    },
  );
  test('selection transforms only selected ink and objects', () {
    final p = NotebookPage(
      id: 'p',
      width: 595,
      height: 842,
      background: const PageBackground.paper(PaperPattern.blank),
      objects: [
        PageObject(
          id: 'text',
          kind: PageObjectKind.text,
          x: 20,
          y: 20,
          width: 100,
          height: 30,
          text: 'Álgebra',
        ),
      ],
      strokes: [
        InkStroke(
          id: 's',
          tool: InkTool.pen,
          argb: 0xff000000,
          width: 2,
          points: [const InkPoint(x: 10, y: 10, pressure: .5)],
        ),
      ],
    );
    final moved = SelectionOperations.translate(p, {
      'text',
    }, const Offset(50, 30));
    expect(moved.objects.single.x, 70);
    expect(moved.strokes.single.points.first.x, 10);
    final tinted = SelectionOperations.recolor(p, {'s', 'text'}, 0xffff0000);
    expect(tinted.objects.single.argb, 0xffff0000);
    expect(tinted.strokes.single.argb, 0xffff0000);
    expect(SelectionOperations.remove(p, {'text'}).objects, isEmpty);
    expect(SelectionOperations.remove(p, {'text'}).strokes, hasLength(1));
  });
  test('favorite tools survive reopening and invalid file recovers', () async {
    final dir = await Directory.systemTemp.createTemp('nala-favorites-');
    addTearDown(() => dir.delete(recursive: true));
    final store = await PenFavoritesController.open(dir.path);
    await store.add(
      PenFavorite(
        id: 'red',
        name: 'Correcciones',
        tool: EditorTool.pen,
        argb: 0xffc14747,
        width: 4,
      ),
    );
    final reopened = await PenFavoritesController.open(dir.path);
    expect(reopened.values.where((f) => f.id == 'red').single.width, 4);
    await File('${dir.path}/pen-favorites.json').writeAsString('{broken');
    final recovered = await PenFavoritesController.open(dir.path);
    expect(recovered.values, isNotEmpty);
  });
}
