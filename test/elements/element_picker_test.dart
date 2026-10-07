import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/page_object.dart';
import 'package:apuntes/elements/element_picker.dart';
import 'package:apuntes/elements/element_store.dart';

Future<void> elementIo(
  WidgetTester tester,
  Future<void> Function() action,
  Future<bool> Function() ready,
) async {
  await action();
  final watch = Stopwatch()..start();
  while (true) {
    await tester.pump();
    if (await ready().timeout(const Duration(seconds: 5)) &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      break;
    }
    if (watch.elapsed.inSeconds >= 5) {
      fail('La biblioteca no respondió.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void main() {
  late Directory directory;
  late ElementStore store;
  final page = NotebookPage(
    id: 'page',
    width: 600,
    height: 800,
    background: const PageBackground.paper(PaperPattern.blank),
    objects: [
      PageObject(
        id: 'text',
        kind: PageObjectKind.text,
        x: 100,
        y: 100,
        width: 200,
        height: 40,
        text: 'Una idea reutilizable',
      ),
    ],
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nala-element-picker-');
    store = ElementStore(root: directory.path);
  });
  tearDown(() async => directory.delete(recursive: true));

  testWidgets(
    'saving prompts for a name and library searches before insertion',
    (tester) async {
      await tester.runAsync(() async {
        LibraryElement? chosen;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed: () => saveSelectionAsElement(
                        context,
                        store: store,
                        page: page,
                        ids: {'text'},
                      ),
                      child: const Text('Guardar'),
                    ),
                    TextButton(
                      onPressed: () async {
                        chosen = await showElementPicker(context, store: store);
                      },
                      child: const Text('Biblioteca'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Mi esquema');
        await tester.pump();
        await elementIo(
          tester,
          () => tester.tap(find.text('Guardar elemento')),
          () async => (await store.load()).length == 1,
        );
        expect((await store.load()).single.name, 'Mi esquema');
        await elementIo(
          tester,
          () => tester.tap(find.text('Biblioteca')),
          () async => find.text('Mi esquema').evaluate().isNotEmpty,
        );
        await tester.enterText(find.byType(TextField), 'ausente');
        await tester.pumpAndSettle();
        expect(find.text('Mi esquema'), findsNothing);
        await tester.enterText(find.byType(TextField), 'ESQUEMA');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mi esquema'));
        await tester.pumpAndSettle();
        expect(chosen!.name, 'Mi esquema');
      });
    },
  );

  testWidgets('library rename and delete update persisted groups', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final saved = await store.saveSelection(
        name: 'Antes',
        page: page,
        ids: {'text'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showElementPicker(context, store: store),
                child: const Text('Biblioteca'),
              ),
            ),
          ),
        ),
      );
      await elementIo(
        tester,
        () => tester.tap(find.text('Biblioteca')),
        () async => find.text('Antes').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Renombrar elemento'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Después');
      await tester.pump();
      await elementIo(
        tester,
        () => tester.tap(find.text('Guardar nombre')),
        () async =>
            (await store.load()).single.name == 'Después' &&
            find.widgetWithText(ListTile, 'Después').evaluate().isNotEmpty,
      );
      expect(find.text('Antes'), findsNothing);
      expect(find.text('Después'), findsOneWidget);
      expect((await store.load()).single.id, saved.id);
      await elementIo(
        tester,
        () => tester.tap(find.byTooltip('Eliminar elemento')),
        () async =>
            (await store.load()).isEmpty &&
            find.text('Todavía no guardaste elementos.').evaluate().isNotEmpty,
      );
      expect(await store.load(), isEmpty);
      expect(find.text('Todavía no guardaste elementos.'), findsOneWidget);
    });
  });
}
