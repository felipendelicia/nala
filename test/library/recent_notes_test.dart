import 'dart:io';

import 'package:apuntes/library/recent_notes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nala-recent-notes-');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('reopens the last five documents with the most recent head', () async {
    final history = await RecentNotes.open(root.path);
    expect(history.entries, isEmpty);
    for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) {
      history.remember(id, '$id-1');
    }
    history.remember('c', 'c-2');

    final expected = [
      (documentId: 'c', headId: 'c-2'),
      (documentId: 'f', headId: 'f-1'),
      (documentId: 'e', headId: 'e-1'),
      (documentId: 'd', headId: 'd-1'),
      (documentId: 'b', headId: 'b-1'),
    ];
    expect(history.entries, expected);
    await history.close();

    final reopened = await RecentNotes.open(root.path);
    expect(reopened.entries, expected);
    await reopened.close();

    final other = await RecentNotes.open(p.join(root.path, 'other-catalog'));
    expect(other.entries, isEmpty);
    await other.close();
  });

  test(
    'recovers from malformed storage on the next successful write',
    () async {
      final file = File(p.join(root.path, 'recent-notes.json'));
      await file.writeAsString('{"entries":');

      final history = await RecentNotes.open(root.path);
      expect(history.entries, isEmpty);
      history.remember('readable', 'revision');
      await history.close();

      final recovered = await RecentNotes.open(root.path);
      expect(recovered.entries, [(documentId: 'readable', headId: 'revision')]);
      await recovered.close();
    },
  );

  test('keeps in-memory history when catalog storage is unavailable', () async {
    final invalidRoot = File(p.join(root.path, 'not-a-directory'));
    await invalidRoot.create();
    final history = RecentNotes(invalidRoot.path);
    history.remember('notebook', 'head');
    expect(history.entries, [(documentId: 'notebook', headId: 'head')]);
    await history.close();
  });
}
