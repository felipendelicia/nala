import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/page_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  testWidgets(
    'mantener pulsada una miniatura permite mover y eliminar con deshacer',
    (tester) async {
      final notebook = fixtureNotebook();
      final repository = MemoryRepository();
      var revision = 0;
      final controller = EditorController(
        notebook: notebook.copyWith(
          pages: [
            ...notebook.pages,
            for (final id in ['page-2', 'page-3'])
              NotebookPage(
                id: id,
                width: 595.28,
                height: 841.89,
                background: const PageBackground.paper(PaperPattern.grid),
              ),
          ],
        ),
        repository: repository,
        deviceId: 'test',
        newId: () => 'page-revision-${revision++}',
        now: () => DateTime.utc(2026),
      );
      addTearDown(controller.dispose);
      await tester.binding.setSurfaceSize(const Size(1100, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: EditorScreen(controller: controller, initialPageIndex: 1),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Páginas'));
      await tester.pumpAndSettle();

      Finder thumbnail(int position) => find.descendant(
        of: find.byType(PagePanel),
        matching: find.text('$position'),
      );
      Iterable<String> pageIds() => controller.notebook.pages.map((p) => p.id);

      await tester.longPress(thumbnail(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mover hoja'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Posición 3'));
      await tester.pumpAndSettle();
      expect(pageIds(), ['page-1', 'page-3', 'page-2']);
      expect(find.text('3/3'), findsOneWidget);

      await tester.longPress(thumbnail(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar hoja'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(pageIds(), ['page-1', 'page-3']);
      expect(find.text('2/2'), findsOneWidget);
      expect((await repository.load(notebook.id))?.pages.map((p) => p.id), [
        'page-1',
        'page-3',
      ]);

      final undo = find.byTooltip('Deshacer');
      await tester.ensureVisible(undo);
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(pageIds(), ['page-1', 'page-3', 'page-2']);
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(pageIds(), ['page-1', 'page-2', 'page-3']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
