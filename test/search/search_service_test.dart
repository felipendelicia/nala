import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/page_comment.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/page_object.dart';
import 'package:apuntes/pdf/pdf_service.dart';
import 'package:apuntes/search/search_service.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';
import '../support/pdf_engine.dart';
import '../support/pdf_fixtures.dart';

void main() {
  test(
    'search finds accented title and comment without manufacturing hits',
    () async {
      final assets = MemoryAssets();
      final pdf = PdfService(assets: assets, initialize: () async {});
      addTearDown(pdf.dispose);
      final notebook = fixtureNotebook();
      final note = notebook.copyWith(
        pages: [
          notebook.pages.single.copyWith(
            comments: [
              PageComment(
                id: 'c',
                x: 1,
                y: 2,
                text: 'Límite y continuidad',
                createdAt: DateTime.utc(2026),
              ),
            ],
          ),
        ],
      );
      final service = SearchService(pdf: pdf, assets: assets);
      final title = await service.search([note], 'algebra');
      expect(title.hits.single.notebookId, 'doc-1');
      expect(title.hits.single.kind, SearchHitKind.title);
      final comment = await service.search([note], 'limite');
      expect(comment.hits.single.pageIndex, 0);
      expect(comment.hits.single.kind, SearchHitKind.comment);
      expect((await service.search([note], 'inexistente')).hits, isEmpty);
    },
  );
  test(
    'recognized text is searchable only while its input fingerprint matches',
    () async {
      final assets = MemoryAssets();
      final pdf = PdfService(assets: assets, initialize: () async {});
      addTearDown(pdf.dispose);
      final note = fixtureNotebook();
      final page = note.pages.single;
      final cached = page.copyWith(
        recognizedText: 'Derivación',
        recognitionFingerprint: await pageRecognitionFingerprint(page),
      );
      final search = SearchService(pdf: pdf, assets: assets);
      final found = await search.search([
        note.copyWith(pages: [cached]),
      ], 'derivacion');
      expect(found.hits.single.kind, SearchHitKind.recognized);
      final changed = cached.copyWith(
        strokes: [
          page.strokes.single.copyWith(
            points: [
              for (final point in page.strokes.single.points)
                InkPoint(x: point.x + 20, y: point.y, pressure: point.pressure),
            ],
          ),
        ],
      );
      expect(
        (await search.search([
          note.copyWith(pages: [changed]),
        ], 'derivacion')).hits,
        isEmpty,
      );
    },
  );
  test(
    'inserted text participates in accent-insensitive page search',
    () async {
      final assets = MemoryAssets();
      final pdf = PdfService(assets: assets, initialize: () async {});
      addTearDown(pdf.dispose);
      final note = fixtureNotebook();
      final page = note.pages.single.copyWith(
        objects: [
          PageObject(
            id: 'text',
            kind: PageObjectKind.text,
            x: 10,
            y: 10,
            width: 100,
            height: 50,
            text: 'Integral de área',
          ),
        ],
      );
      final found = await SearchService(pdf: pdf, assets: assets).search([
        note.copyWith(pages: [page]),
      ], 'area');
      expect(found.hits.single.kind, SearchHitKind.text);
      expect(found.hits.single.snippet, 'Integral de área');
    },
  );
  test(
    'extract original PDF text and report missing PDF as partial search',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nala-search-pdf-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final assets = MemoryAssets();
      final pdf = PdfService(
        assets: assets,
        initialize: () => initializePdfForTest(directory.path),
      );
      addTearDown(pdf.dispose);
      final note = await pdf.importDocument(
        bytes: await makeFixturePdf(),
        title: 'Documento',
        documentId: 'pdf',
        newId: () => 'page',
        now: DateTime.utc(2026),
      );
      final search = SearchService(pdf: pdf, assets: assets);
      final found = await search.search([note], 'nala pdf test');
      expect(found.hits.map((h) => h.pageIndex), [0, 1]);
      assets.assets.clear();
      final partial = await SearchService(
        pdf: pdf,
        assets: assets,
      ).search([note], 'nala');
      expect(partial.hits, isEmpty);
      expect(partial.failures, hasLength(2));
    },
  );
}
