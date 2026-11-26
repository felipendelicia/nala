import 'package:apuntes/document/deferred_notebook_page.dart';
import 'package:apuntes/document/markdown_content.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/notebook_codec.dart';
import 'package:apuntes/editor/markdown_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NotebookPage _storedMarkdownPage(String markdown) => NotebookPage.fromJson({
  'id': 'saved-markdown',
  'width': markdownSheetWidth,
  'height': markdownSheetHeight,
  'background': {'kind': 'paper', 'pattern': 'blank'},
  'strokes': <Map<String, dynamic>>[],
  'markdown': markdown,
});

void main() {
  testWidgets('editar una hoja Markdown larga la continúa en hojas A4', (
    tester,
  ) async {
    final sections = List.generate(
      40,
      (index) =>
          '## Sección $index\n\n'
          '${'Una idea que necesita varias líneas en la hoja. ' * 5}'
          'Cierre $index.',
    );
    var id = 0;
    final saved = _storedMarkdownPage('# Resumen original');
    final sheets = updateMarkdownSheets(
      saved,
      sections.join('\n\n'),
      newId: () => '${id++}',
    );
    expect(sheets.length, greaterThan(1));
    expect(sheets.first.id, saved.id);
    expect(sheets.map((page) => page.id).toSet(), hasLength(sheets.length));
    expect(
      sheets.map((page) => page.markdown).join('\n\n'),
      contains('Cierre 39.'),
    );
    for (final page in sheets) {
      expect(page.width, 595.28);
      expect(page.height, 841.89);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(
                    boldText: true,
                    textScaler: const TextScaler.linear(2),
                  )
                  .applyTextStyleOverrides(
                    letterSpacingOverride: 4,
                    lineHeightScaleFactorOverride: 2,
                    paragraphSpacingOverride: null,
                    wordSpacingOverride: null,
                  ),
              child: DefaultTextStyle(
                style: const TextStyle(
                  fontSize: 30,
                  letterSpacing: 4,
                  height: 3,
                ),
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: page.width,
                    height: page.height,
                    child: MarkdownSheet(page: page),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  test('una línea larga y un bloque de código conservan texto y estilo', () {
    final line = List.generate(900, (i) => 'palabra$i').join(' ');
    final code = List.generate(90, (i) => 'print("línea $i");').join('\n');
    var id = 0;
    final pages = updateMarkdownSheets(
      _storedMarkdownPage('# Resumen original'),
      '**$line**\n\n```dart\n$code\n```',
      newId: () => '${id++}',
    );
    final blocks = pages
        .expand((page) => parseMarkdown(page.markdown!))
        .toList();
    expect(
      blocks
          .where((block) => block.code)
          .map((b) => b.runs.single.text)
          .join('\n'),
      code,
    );
    final boldRuns = blocks
        .where((block) => !block.code)
        .expand((b) => b.runs)
        .where((run) => run.text.trim().isNotEmpty);
    expect(
      boldRuns
          .where((run) => !run.emphasis.contains(MarkdownEmphasis.bold))
          .map((run) => run.text.characters.take(40).join()),
      isEmpty,
    );
    expect(
      boldRuns.map((run) => run.text).join(' ').split(RegExp(r'\s+')),
      line.split(' '),
    );
  });

  testWidgets('una hoja guardada con poco espacio sigue mostrando el resumen', (
    tester,
  ) async {
    final page = NotebookPage(
      id: 'legacy',
      width: 595.28,
      height: 190,
      background: const PageBackground.paper(PaperPattern.blank),
      markdown:
          '# Resumen guardado\n\n${'Una línea larga para la hoja. ' * 300}\n\nFin.',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: page.width,
            height: page.height,
            child: MarkdownSheet(page: page),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Resumen guardado', findRichText: true), findsOneWidget);
    expect(find.text('Fin.', findRichText: true), findsOneWidget);
    expect(
      tester.getBottomRight(find.text('Fin.', findRichText: true)).dy,
      lessThan(tester.getBottomRight(find.byType(MarkdownSheet)).dy),
    );
  });

  test('restaurar y copiar una hoja conserva el Markdown original', () {
    const markdown = '# Repaso\n\n**La respuesta** está en la hoja 3.';
    final book = Notebook.blank(
      id: 'book',
      pageId: 'page',
      title: 'Física',
      pattern: PaperPattern.blank,
      now: DateTime.utc(2026),
    );
    final page = _storedMarkdownPage(markdown);
    final loaded = NotebookCodec.decode(
      NotebookCodec.encode(book.copyWith(pages: [...book.pages, page])),
    );
    expect(loaded.pages.first.markdown, isNull);
    final restored = loaded.pages.last;
    expect(restored.markdown, markdown);
    expect(restored.toJson()['markdown'], markdown);

    final editing = DeferredNotebookPage(
      id: restored.id,
      width: restored.width,
      height: restored.height,
      background: restored.background,
      decoded: restored,
      encoded: '',
    );
    expect(editing.markdown, markdown);
    expect(editing.copyWith().markdown, markdown);
    expect(
      updateMarkdownSheets(
        editing,
        '# Repaso corregido',
        newId: () => 'overflow',
      ).single.id,
      restored.id,
    );
  });

  testWidgets('tocar una referencia entrega el destino a Nala', (tester) async {
    final destinations = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: MarkdownContent(
              markdown: '[Hoja 3](nala-page:hoja-3)',
              onLink: destinations.add,
            ),
          ),
        ),
      ),
    );
    final reference = find.text('Hoja 3', findRichText: true);
    await tester.tapAt(tester.getTopLeft(reference) + const Offset(12, 10));
    expect(destinations, ['nala-page:hoja-3']);
  });
}
