import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/page_object.dart';
import 'package:apuntes/editor/selection_operations.dart';

void main() {
  final locked = PageObject.fromJson({
    'id': 'locked',
    'kind': 'text',
    'x': 200,
    'y': 200,
    'width': 100,
    'height': 30,
    'text': 'Locked',
    'locked': true,
  });
  final free = PageObject.fromJson({
    'id': 'free',
    'kind': 'text',
    'x': 20,
    'y': 20,
    'width': 50,
    'height': 30,
    'text': 'Free',
  });
  final page = NotebookPage(
    id: 'p',
    width: 500,
    height: 700,
    background: const PageBackground.paper(PaperPattern.blank),
    objects: [locked, free],
  );
  final stale = {'locked', 'free'};
  test('new selection excludes locked content', () {
    expect(
      SelectionOperations.within(page, const Rect.fromLTWH(0, 0, 500, 700)),
      {'free'},
    );
  });
  test(
    'stale selections cannot remove, move, resize, rotate or recolor locks',
    () {
      final changed = [
        SelectionOperations.remove(page, stale),
        SelectionOperations.translate(page, stale, const Offset(40, 50)),
        SelectionOperations.scale(page, stale, 2),
        SelectionOperations.rotate(page, stale, 1),
        SelectionOperations.recolor(page, stale, 0xff777777),
      ];
      for (final result in changed) {
        expect(
          result.objects.singleWhere((o) => o.id == 'locked').toJson(),
          locked.toJson(),
        );
      }
      expect(changed[1].objects.last.x, 60);
      expect(changed[2].objects.last.x, 20);
    },
  );
  test('clipboard cut capture excludes locked content even with stale IDs', () {
    final clip = SelectionClipboard()..capture(page, stale, forCut: true);
    var next = 0;
    final result = clip.paste(
      page.copyWith(objects: []),
      const Offset(10, 10),
      newId: () => 'copy-${next++}',
    );
    expect(result.objects.map((o) => o.text), ['Free']);
  });
}
