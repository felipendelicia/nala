import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/page_comment.dart';
import 'package:apuntes/document/page_link.dart';
import 'package:apuntes/document/page_object.dart';
import 'package:apuntes/editor/comment_dialog.dart';
import 'package:apuntes/editor/editor_controller.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/editor/paper_canvas.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  for (final pin in [false, true]) {
    testWidgets(
      pin
          ? 'comment pin takes precedence over linked object'
          : 'reading tap opens link and dragging keeps navigation',
      (tester) async {
        var opened = 0;
        final book = fixtureNotebook();
        final controller = EditorController(
          notebook: book.copyWith(
            pages: [
              book.pages.single.copyWith(
                objects: [
                  PageObject(
                    id: 'link',
                    kind: PageObjectKind.text,
                    x: 100,
                    y: 100,
                    width: 160,
                    height: 60,
                    text: 'Destino',
                    link: PageLink(notebookId: 'other', pageId: 'target'),
                  ),
                ],
                comments: pin
                    ? [
                        PageComment(
                          id: 'pin',
                          x: 120,
                          y: 120,
                          text: 'Consultar',
                          createdAt: DateTime.utc(2026),
                        ),
                      ]
                    : [],
              ),
            ],
          ),
          repository: MemoryRepository(),
          deviceId: 'test',
          newId: () => 'r',
          now: DateTime.now,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: EditorScreen(
              controller: controller,
              onOpenLink: (_) => opened++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Modo lectura'));
        await tester.pumpAndSettle();
        final canvas = tester.renderObject<RenderBox>(
          find.byType(PaperCanvas).first,
        );
        final point = canvas.localToGlobal(const Offset(120, 120));
        await tester.tapAt(point);
        await tester.pumpAndSettle();
        if (pin) {
          expect(opened, 0);
          expect(find.byType(CommentDialog), findsOneWidget);
        } else {
          expect(opened, 1);
          await tester.dragFrom(point, const Offset(0, 45));
          await tester.pumpAndSettle();
          expect(opened, 1);
          expect(
            controller.notebook.pages.single.objects.single.text,
            'Destino',
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }
}
