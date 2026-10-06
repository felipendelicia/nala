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
    String? headId,
  })
    // Public argument names differ from private storage fields.
    // ignore: prefer_initializing_formals
    : _notebook = notebook,
       _headId = headId;
  final NotebookRepository repository;
  final String deviceId;
  final String Function() newId;
  final DateTime Function() now;
  Notebook _notebook;
  String? _headId;
  Object? savingError;
  bool saving = false, _disposed = false;
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
    _undo.add(_notebook);
    _redo.clear();
    _notebook = edit(_notebook).copyWith(updatedAt: now().toUtc());
    return _save(_notebook);
  }

  Future<void> undo() {
    if (_undo.isEmpty) return Future.value();
    _redo.add(_notebook);
    _notebook = _undo.removeLast().copyWith(updatedAt: now().toUtc());
    return _save(_notebook);
  }

  Future<void> redo() {
    if (_redo.isEmpty) return Future.value();
    _undo.add(_notebook);
    _notebook = _redo.removeLast().copyWith(updatedAt: now().toUtc());
    return _save(_notebook);
  }

  Future<void> retrySave() => _save(_notebook);
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
