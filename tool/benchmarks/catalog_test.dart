import 'dart:io';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('catálogo denso sintético', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nala-catalog-perf-',
    );
    final path = '${directory.path}/notes.db';
    final repository = await SqliteNotebookRepository.open(path);
    addTearDown(() async {
      await repository.close();
      await directory.delete(recursive: true);
    });
    final now = DateTime.utc(2026);
    const count = 14,
        pagesPerBook = 14,
        strokesPerPage = 18,
        pointsPerStroke = 32;
    final books = [
      for (var book = 0; book < count; book++)
        Notebook(
          id: 'book-$book',
          title: 'Sintético $book',
          subject: 'Prueba',
          updatedAt: now,
          pages: [
            for (var page = 0; page < pagesPerBook; page++)
              NotebookPage(
                id: 'page-$page',
                width: 595.28,
                height: 841.89,
                background: const PageBackground.paper(PaperPattern.grid),
                strokes: [
                  for (var stroke = 0; stroke < strokesPerPage; stroke++)
                    InkStroke(
                      id: '$page-$stroke',
                      tool: InkTool.pen,
                      argb: 0xff202020,
                      width: 2,
                      points: [
                        for (var point = 0; point < pointsPerStroke; point++)
                          InkPoint(
                            x: 10 + point * 2.1,
                            y: stroke * 7.9 + point / 2,
                            pressure: .6,
                          ),
                      ],
                    ),
                ],
              ),
          ],
        ),
    ];
    final sql = sqlite3.open(path);
    try {
      sql.execute('BEGIN');
      for (var index = 0; index < books.length; index++) {
        final revision = Revision(
          id: 'head-$index',
          parentId: null,
          deviceId: 'fixture',
          createdAt: now,
          notebook: books[index],
        );
        sql.execute(
          'INSERT INTO revisions (id, document_id, parent_id, payload, frozen) VALUES (?, ?, ?, ?, 1)',
          [
            revision.id,
            revision.notebook.id,
            null,
            NotebookCodec.encodeRevision(revision),
          ],
        );
      }
      sql.execute('COMMIT');
    } finally {
      sql.close();
    }
    final initial = Stopwatch()..start();
    expect(await repository.list(), hasLength(count));
    initial.stop();
    for (var index = 0; index < 2; index++) {
      await repository.list();
    }
    final unchanged = <int>[];
    for (var index = 0; index < 9; index++) {
      final watch = Stopwatch()..start();
      expect(await repository.list(), hasLength(count));
      unchanged.add(watch.elapsedMicroseconds);
    }
    final changed = <int>[];
    var previous = 'head-0';
    for (var index = 0; index < 5; index++) {
      final revision = Revision(
        id: 'edit-$index',
        parentId: previous,
        deviceId: 'fixture',
        createdAt: now,
        notebook: books.first.copyWith(title: 'Editado $index'),
      );
      await repository.acceptRemote(revision);
      previous = revision.id;
      final watch = Stopwatch()..start();
      final catalog = await repository.list();
      changed.add(watch.elapsedMicroseconds);
      expect(
        catalog.where((entry) => entry.headId == revision.id),
        hasLength(1),
      );
    }
    unchanged.sort();
    changed.sort();
    debugPrint(
      'CATALOG_PERF points=${count * pagesPerBook * strokesPerPage * pointsPerStroke} cold_us=${initial.elapsedMicroseconds} unchanged_median_us=${unchanged[4]} one_changed_median_us=${changed[2]} unchanged_samples=$unchanged one_changed_samples=$changed',
    );
  });
}
