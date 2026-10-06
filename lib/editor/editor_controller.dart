import 'dart:async';
import 'package:flutter/foundation.dart';
import '../document/notebook.dart';
import '../document/notebook_repository.dart';
import '../document/revision.dart';

class EditorController extends ChangeNotifier {
  EditorController({
    required Notebook notebook,
    required this.repository,
    required this.deviceId,
    required this.newId,
    required this.now,
    this._headId,
  })
    // Public argument names differ from private storage fields.
    // ignore: prefer_initializing_formals
    : _notebook = notebook;
  final NotebookRepository repository;
  final String deviceId;
  final String Function() newId;
  final DateTime Function() now;
  Notebook _notebook;
  String? _headId;
  Object? savingError;
  bool saving = false, _disposed = false;
  int _editGeneration = 0;
  Future<void> _queue = Future.value();
  final List<Notebook> _undo = [], _redo = [];
  Notebook get notebook => _notebook;
  String? get headId => _headId;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> apply(Notebook Function(Notebook) edit) {
    _editGeneration++;
    _undo.add(_notebook);
    _redo.clear();
    _notebook = edit(_notebook).copyWith(updatedAt: now().toUtc());
    return _save(_notebook);
  }

  Future<void> undo() {
    if (_undo.isEmpty) return Future.value();
    _editGeneration++;
    _redo.add(_notebook);
    _notebook = _undo.removeLast().copyWith(updatedAt: now().toUtc());
    return _save(_notebook);
  }

  Future<void> redo() {
    if (_redo.isEmpty) return Future.value();
    _editGeneration++;
    _undo.add(_notebook);
    _notebook = _redo.removeLast().copyWith(updatedAt: now().toUtc());
    return _save(_notebook);
  }

  Future<void> retrySave() {
    _editGeneration++;
    return _save(_notebook);
  }

  Future<bool> refreshRemote({required bool Function() canApply}) async {
    if (_disposed || !canApply()) return false;
    await flush();
    final generation = _editGeneration, previous = _headId;
    if (previous == null) return false;
    final heads = (await repository.list())
        .where((e) => e.notebook.id == _notebook.id)
        .toList();
    if (heads.length != 1 || heads.single.headId == previous) return false;
    final history = {
      for (final r in await repository.history(_notebook.id)) r.id: r,
    };
    final seen = <String>{};
    String? cursor = heads.single.headId;
    while (cursor != null && cursor != previous && seen.add(cursor)) {
      cursor = history[cursor]?.parentId;
    }
    if (cursor != previous ||
        _disposed ||
        generation != _editGeneration ||
        _headId != previous ||
        !canApply() ||
        saving ||
        savingError != null) {
      return false;
    }
    _notebook = heads.single.notebook;
    _headId = heads.single.headId;
    _undo.clear();
    _redo.clear();
    _notify();
    return true;
  }

  Future<void> _save(Notebook snapshot) {
    saving = true;
    _notify();
    _queue = _queue.then((_) async {
      try {
        final revision = Revision(
          id: newId(),
          deviceId: deviceId,
          parentId: _headId,
          createdAt: now().toUtc(),
          notebook: snapshot,
        );
        await repository.commit(revision);
        _headId = revision.id;
        savingError = null;
      } catch (error) {
        savingError = error;
      }
    });
    final current = _queue;
    return current.then((_) {
      if (identical(current, _queue)) saving = false;
      _notify();
    });
  }

  Future<void> flush() async {
    await _queue;
    if (savingError != null) throw StateError('No se pudo guardar el cuaderno');
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
