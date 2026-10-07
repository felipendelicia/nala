import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/links/page_link_picker.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  testWidgets(
    'picker searches notebook and page text and returns exact destination',
    (tester) async {
      final repository = MemoryRepository();
      final book = fixtureNotebook().copyWith(
        pages: [
          fixtureNotebook().pages.first,
          NotebookPage(
            id: 'page-2',
            width: 595,
            height: 842,
            background: const PageBackground.paper(PaperPattern.blank),
            recognizedText: 'Derivadas e integrales',
          ),
        ],
      );
      await repository.commit(
        Revision(
          id: 'head',
          deviceId: 'device',
          parentId: null,
          createdAt: DateTime.utc(2026, 10, 7),
          notebook: book,
        ),
      );
      PageLinkChoice? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  chosen = await showPageLinkPicker(
                    context,
                    repository: repository,
                  );
                },
                child: const Text('Elegir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Elegir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'integrales');
      await tester.pumpAndSettle();
      expect(find.text('Página 1'), findsNothing);
      expect(find.text('Página 2'), findsOneWidget);
      await tester.tap(find.text('Página 2'));
      await tester.pumpAndSettle();
      expect(chosen!.link.notebookId, 'doc-1');
      expect(chosen!.link.pageId, 'page-2');
      expect(chosen!.label, 'Álgebra · Página 2');
    },
  );

  testWidgets('empty repository offers recoverable cancel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showPageLinkPicker(context, repository: MemoryRepository()),
              child: const Text('Elegir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Elegir'));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no hay páginas para enlazar.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
