import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

typedef RecentNote = ({String documentId, String headId});

class RecentNotes extends ChangeNotifier {
  RecentNotes([String? root])
    : _file = root == null ? null : File(p.join(root, 'recent-notes.json'));

  static const _limit = 5;
  final File? _file;
  List<RecentNote> _entries = const [];
  Future<void>? _writes;
  Future<void>? _closing;
  bool _disposed = false;

  List<RecentNote> get entries => _entries;

  static Future<RecentNotes> open(String root) async {
    final history = RecentNotes(root);
    try {
      if (jsonDecode(await history._file!.readAsString()) case {
        'version': 1,
        'entries': final List<Object?> stored,
      }) {
        final entries = <RecentNote>[];
        final seen = <String>{};
        for (final value in stored) {
          if (value case {
            'documentId': final String id,
            'headId': final String head,
          } when id.isNotEmpty && head.isNotEmpty && seen.add(id)) {
            entries.add((documentId: id, headId: head));
            if (entries.length == _limit) break;
          }
        }
        history._entries = List.unmodifiable(entries);
      }
    } on FileSystemException {
      // The history is optional and may not exist yet.
    } on FormatException {
      // The next recorded visit replaces a malformed history.
    }
    return history;
  }

  void remember(String documentId, String headId) {
    if (_disposed || _closing != null || documentId.isEmpty || headId.isEmpty) {
      return;
    }
    final entry = (documentId: documentId, headId: headId);
    if (_entries.firstOrNull == entry) return;

    final snapshot = _entries = List.unmodifiable(
      [
        entry,
        ..._entries.where((entry) => entry.documentId != documentId),
      ].take(_limit),
    );
    if (_file case final File file) {
      _writes =
          _writes?.then((_) => _persist(file, snapshot)) ??
          _persist(file, snapshot);
    }
    notifyListeners();
  }

  Future<void> _persist(File file, List<RecentNote> snapshot) async {
    final staged = File('${file.path}.${const Uuid().v4()}.tmp');
    try {
      await file.parent.create(recursive: true);
      try {
        await staged.writeAsString(
          jsonEncode({
            'version': 1,
            'entries': [
              for (final entry in snapshot)
                {'documentId': entry.documentId, 'headId': entry.headId},
            ],
          }),
          flush: true,
        );
        await staged.rename(file.path);
      } finally {
        if (await staged.exists()) await staged.delete();
      }
    } on FileSystemException {
      // An unavailable catalog can still show the in-memory history.
    }
  }

  Future<void> close() {
    if (_writes case final Future<void> pending) {
      return _closing ??= pending.then((_) => dispose());
    }
    dispose();
    return Future.value();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
