import 'dart:convert';

import 'package:apuntes/document/deferred_notebook_page.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

DeferredNotebookPage _deferred(NotebookPage page, {String? encoded}) =>
    DeferredNotebookPage(
      id: page.id,
      width: page.width,
      height: page.height,
      background: page.background,
      encoded: encoded ?? jsonEncode(page.toJson()),
    );

void main() {
  test('layout reads metadata before the deferred contents are ready', () async {
    final original = fixtureNotebook().pages.single;
    final page = _deferred(original);

    expect(page.id, original.id);
    expect(page.width, original.width);
    expect(page.background.pattern, original.background.pattern);
    expect(page.isReady, isFalse);

    final first = page.prepare();
    final second = page.prepare();
    expect(first, same(second));
    await first;

    expect(page.isReady, isTrue);
    expect(page.toJson(), original.toJson());
    expect(page.strokes, same(page.strokes));
  });

  test('reuses a ready preview only for the identical encoded page', () {
    final original = fixtureNotebook().pages.single;
    final preview = _deferred(original)..materialize();
    final unchanged = _deferred(original);
    final changed = _deferred(original.copyWith(strokes: []));

    expect(unchanged.reuseDecodedPage(preview), isTrue);
    expect(unchanged.strokes, same(preview.strokes));
    expect(changed.reuseDecodedPage(preview), isFalse);
    expect(changed.isReady, isFalse);
  });

  test('serializing unread content validates and preserves the whole page', () {
    final original = fixtureNotebook().pages.single;
    final valid = _deferred(original);
    final invalid = _deferred(
      original,
      encoded: jsonEncode({...original.toJson(), 'strokes': ['bad stroke']}),
    );

    expect(valid.toJson(), original.toJson());
    expect(invalid.toJson, throwsFormatException);
    expect(invalid.isReady, isFalse);
  });
}
