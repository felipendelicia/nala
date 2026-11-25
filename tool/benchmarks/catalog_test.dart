import 'dart:io';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/document/sqlite_notebook_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> _sampleFirstRead<T>(
  String path,
  List<int> samples,
  Future<T> Function(SqliteNotebookRepository) read,
  void Function(T) verify,
) async {
  final repository = await SqliteNotebookRepository.open(path);
  try {
    final watch = Stopwatch()..start();
    final result = await read(repository);
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
    verify(result);
  } finally {
    await repository.close();
  }
}

int _median(List<int> samples) =>
    (samples.toList()..sort())[samples.length ~/ 2];

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

    // Each read starts with a fresh SQLite connection and repository worker.
    // The fixture and OS file cache are shared. Rotate the read order and
    // exclude repository startup so the four timings compare query work.
    const rounds = 5;
    const documentId = 'book-7', headId = 'head-7';
    final fullList = <int>[],
        metadata = <int>[],
        notebook = <int>[],
        preview = <int>[];
    final reads = <Future<void> Function()>[
      () => _sampleFirstRead(path, fullList, (repo) => repo.list(), (entries) {
        expect(entries, hasLength(count));
        expect(
          entries.singleWhere((entry) => entry.headId == headId).notebook.pages,
          hasLength(pagesPerBook),
        );
      }),
      () => _sampleFirstRead(path, metadata, (repo) => repo.listCatalog(), (
        entries,
      ) {
        expect(entries, hasLength(count));
        final entry = entries.singleWhere(
          (entry) => entry.documentId == documentId,
        );
        expect(entry.headId, headId);
        expect(entry.pageCount, pagesPerBook);
      }),
      () => _sampleFirstRead(
        path,
        notebook,
        (repo) => repo.load(documentId, headId: headId),
        (book) {
          expect(book?.id, documentId);
          expect(book?.pages, hasLength(pagesPerBook));
          expect(
            book?.pages.first.strokes.first.points,
            hasLength(pointsPerStroke),
          );
        },
      ),
      () => _sampleFirstRead(
        path,
        preview,
        (repo) => repo.loadPreview(documentId, headId: headId),
        (page) {
          expect(page?.id, 'page-0');
          expect(page?.strokes, hasLength(strokesPerPage));
          expect(page?.strokes.first.points, hasLength(pointsPerStroke));
        },
      ),
    ];
    for (var round = 0; round < rounds; round++) {
      for (var offset = 0; offset < reads.length; offset++) {
        await reads[(round + offset) % reads.length]();
      }
    }
    debugPrint(
      'CATALOG_FIRST_READ_PERF rounds=$rounds fresh_connections=true '
      'repository_open_timed=false os_cache_flushed=false '
      'full_list_median_us=${_median(fullList)} metadata_median_us=${_median(metadata)} '
      'exact_head_median_us=${_median(notebook)} preview_median_us=${_median(preview)} '
      'full_list_samples=$fullList metadata_samples=$metadata '
      'exact_head_samples=$notebook preview_samples=$preview',
    );

    final metadataRepository = await SqliteNotebookRepository.open(path);
    final metadataUnchanged = <int>[], metadataChanged = <int>[];
    try {
      for (var index = 0; index < 2; index++) {
        await metadataRepository.listCatalog();
      }
      for (var index = 0; index < 9; index++) {
        final watch = Stopwatch()..start();
        final catalog = await metadataRepository.listCatalog();
        metadataUnchanged.add(watch.elapsedMicroseconds);
        expect(catalog, hasLength(count));
      }
      for (var index = 0; index < 5; index++) {
        final title = 'Metadatos editados $index';
        final revision = Revision(
          id: 'metadata-edit-$index',
          parentId: previous,
          deviceId: 'fixture',
          createdAt: now,
          notebook: books.first.copyWith(title: title),
        );
        await metadataRepository.acceptRemote(revision);
        previous = revision.id;
        final watch = Stopwatch()..start();
        final catalog = await metadataRepository.listCatalog();
        metadataChanged.add(watch.elapsedMicroseconds);
        expect(catalog, hasLength(count));
        final entry = catalog.singleWhere(
          (entry) => entry.documentId == revision.notebook.id,
        );
        expect(entry.headId, revision.id);
        expect(entry.title, title);
      }
    } finally {
      await metadataRepository.close();
    }
    debugPrint(
      'CATALOG_METADATA_WARM_PERF warmup_reads=2 mutation_timed=false '
      'unchanged_median_us=${_median(metadataUnchanged)} one_changed_median_us=${_median(metadataChanged)} '
      'unchanged_samples=$metadataUnchanged one_changed_samples=$metadataChanged',
    );
  });
}
