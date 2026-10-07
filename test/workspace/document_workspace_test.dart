import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/revision.dart';
import 'package:apuntes/workspace/document_workspace.dart';
import '../support/fixtures.dart';
import '../support/memory_repository.dart';

void main() {
  test(
    'open tab retains its controller and split has one input owner',
    () async {
      final workspace = DocumentWorkspace(
        repository: MemoryRepository(),
        deviceId: 'pc',
        newId: () => DateTime.now().microsecondsSinceEpoch.toString(),
        now: () => DateTime.utc(2026),
      );
      addTearDown(workspace.dispose);
      DocumentEntry entry(String id) => DocumentEntry(
        notebook: fixtureNotebook(id: id),
        headId: 'head-$id',
        deviceId: 'pc',
        isConflict: false,
      );
      final first = workspace.open(entry('a'));
      await first.controller.apply((n) => n.copyWith(title: 'Cambió'));
      final second = workspace.open(entry('b'));
      workspace.select(first.id);
      expect(identical(workspace.open(entry('a')), first), isTrue);
      expect(first.controller.notebook.title, 'Cambió');
      workspace.splitWith(second.id);
      expect(workspace.visibleIds, ['a', 'b']);
      workspace.focus('b');
      expect(workspace.activeId, 'b');
      expect(workspace.isActive('a'), isFalse);
      expect(workspace.isActive('b'), isTrue);
      await workspace.close('b');
      expect(workspace.visibleIds, ['a']);
      expect(workspace.activeId, 'a');
    },
  );
  test(
    'failed save keeps tab open and its unsaved controller available',
    () async {
      final workspace = DocumentWorkspace(
        repository: FailingRepository(),
        deviceId: 'pc',
        newId: () => 'revision',
        now: () => DateTime.utc(2026),
      );
      addTearDown(workspace.dispose);
      final tab = workspace.open(
        DocumentEntry(
          notebook: fixtureNotebook(),
          headId: 'head',
          deviceId: 'pc',
          isConflict: false,
        ),
      );
      await tab.controller.apply((n) => n.copyWith(title: 'Sin guardar'));
      await expectLater(workspace.close(tab.id), throwsStateError);
      expect(workspace.tabs.single.controller.notebook.title, 'Sin guardar');
      expect(workspace.activeId, 'doc-1');
    },
  );
}

class FailingRepository extends MemoryRepository {
  @override
  Future<void> commit(Revision revision) async =>
      throw const FileSystemException('no space');
}
