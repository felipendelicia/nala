import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/page_link.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/workspace/document_workspace.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  test('link reuses unsaved open controller and targets exact page', () async {
    final repo = MemoryRepository();
    final first = fixtureNotebook(id: 'a');
    final second = fixtureNotebook(id: 'b').copyWith(
      pages: [
        ...fixtureNotebook(id: 'b').pages,
        NotebookPage(
          id: 'destination',
          width: 595,
          height: 842,
          background: PageBackground.paper(PaperPattern.blank),
        ),
      ],
    );
    await repo.commit(
      Revision(
        id: 'ra',
        deviceId: 'pc',
        parentId: null,
        createdAt: DateTime.utc(2026),
        notebook: first,
      ),
    );
    await repo.commit(
      Revision(
        id: 'rb',
        deviceId: 'pc',
        parentId: null,
        createdAt: DateTime.utc(2026),
        notebook: second,
      ),
    );
    var n = 0;
    final workspace = DocumentWorkspace(
      repository: repo,
      deviceId: 'pc',
      newId: () => 'revision-${n++}',
      now: DateTime.now,
    );
    addTearDown(workspace.dispose);
    final tabs = await repo.list();
    final open = workspace.open(tabs.firstWhere((e) => e.notebook.id == 'b'));
    await open.controller.apply(
      (book) => book.copyWith(title: 'Cambios propios'),
    );
    workspace.open(tabs.firstWhere((e) => e.notebook.id == 'a'));
    expect(
      await workspace.openLink(
        PageLink(notebookId: 'b', pageId: 'destination'),
      ),
      isTrue,
    );
    expect(workspace.activeId, 'b');
    expect(
      identical(workspace.tabs.firstWhere((t) => t.id == 'b'), open),
      isTrue,
    );
    expect(open.controller.notebook.title, 'Cambios propios');
    expect(open.requestedPageId, 'destination');
    final token = open.navigationRequest;
    expect(
      await workspace.openLink(
        PageLink(notebookId: 'b', pageId: 'destination'),
      ),
      isTrue,
    );
    expect(open.navigationRequest, greaterThan(token));
    expect(
      await workspace.openLink(PageLink(notebookId: 'b', pageId: 'missing')),
      isFalse,
    );
    expect(
      await workspace.openLink(
        PageLink(notebookId: 'missing', pageId: 'missing'),
      ),
      isFalse,
    );
    expect(workspace.tabs.length, 2);
  });
}
