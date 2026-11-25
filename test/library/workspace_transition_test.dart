import 'dart:async';

import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/editor/editor_screen.dart';
import 'package:apuntes/library/library_controller.dart';
import 'package:apuntes/library/library_screen.dart';
import 'package:apuntes/ui/app_theme.dart';
import 'package:apuntes/workspace/document_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/memory_repository.dart';

class _CountingRepository extends MemoryRepository {
  int catalogReads = 0;
  Completer<void>? pendingSave;

  @override
  Future<void> commit(Revision revision) async {
    await pendingSave?.future;
    await super.commit(revision);
  }

  @override
  Future<List<DocumentEntry>> list() {
    catalogReads++;
    return super.list();
  }
}

Future<_CountingRepository> _mountLibrary(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(820, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repository = _CountingRepository();
  final library = LibraryController(repository: repository, deviceId: 'tablet');
  final services = AppServices(
    root: '/unused',
    deviceId: 'tablet',
    repository: repository,
    library: library,
    assets: MemoryAssets(),
  );
  addTearDown(services.close);
  final note = fixtureNotebook();
  await library.add(note);
  await tester.pumpWidget(
    MaterialApp(
      theme: nalaTheme().copyWith(platform: TargetPlatform.android),
      home: LibraryScreen(services: services),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<_CountingRepository> _openNotebook(WidgetTester tester) async {
  final repository = await _mountLibrary(tester);
  await tester.tap(find.text(fixtureNotebook().title));
  await tester.pump();
  return repository;
}

double _workspaceOffset(WidgetTester tester) => tester
    .widget<SlideTransition>(
      find.ancestor(
        of: find.byType(WorkspaceScreen, skipOffstage: false),
        matching: find.byType(SlideTransition, skipOffstage: false),
      ),
    )
    .position
    .value
    .dx;

void main() {
  testWidgets('la entrada responde pronto y desacelera antes de terminar', (
    tester,
  ) async {
    await _openNotebook(tester);
    final start = _workspaceOffset(tester);
    expect(start, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 22));
    expect(1 - _workspaceOffset(tester) / start, inInclusiveRange(.12, .31));
    await tester.pump(const Duration(milliseconds: 208));
    final workspace = tester.element(find.byType(WorkspaceScreen));
    expect(
      ModalRoute.of(workspace)!.animation!.status,
      AnimationStatus.completed,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('el regreso se mueve desde el inicio y difiere la recarga', (
    tester,
  ) async {
    final repository = await _openNotebook(tester);
    await tester.pumpAndSettle();
    final before = repository.catalogReads;

    await tester.tap(find.byTooltip('Volver a mis apuntes'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(repository.catalogReads, before);
    expect(_workspaceOffset(tester), inInclusiveRange(.01, .025));

    await tester.pumpAndSettle();
    expect(repository.catalogReads, before + 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('volver al catálogo espera el guardado pendiente', (
    tester,
  ) async {
    final repository = await _openNotebook(tester);
    await tester.pumpAndSettle();
    final editor = tester.widget<EditorScreen>(find.byType(EditorScreen));
    final save = repository.pendingSave = Completer<void>();
    unawaited(
      editor.controller.apply((note) => note.copyWith(title: 'Editado')),
    );

    await tester.tap(find.byTooltip('Volver a mis apuntes'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(_workspaceOffset(tester), 0);
    expect(editor.controller.saving, isTrue);

    save.complete();
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceScreen), findsNothing);
    expect(find.text('Editado'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (tooltip, item) in [
    ('Más opciones de la biblioteca', 'Backup de la biblioteca'),
    ('Opciones de apunte', 'Eliminar apunte'),
  ]) {
    testWidgets('el menú $tooltip aparece completo con el primer toque', (
      tester,
    ) async {
      await _mountLibrary(tester);
      await tester.tap(find.byTooltip(tooltip));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final option = tester.element(find.text(item));
      expect(
        ModalRoute.of(option)!.animation!.status,
        AnimationStatus.completed,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
