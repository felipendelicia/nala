import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../document/notebook.dart';
import '../document/notebook_repository.dart';
import '../document/revision.dart';

class LibraryController extends ChangeNotifier {
  LibraryController({required this.repository, required this.deviceId});
  final NotebookRepository repository;
  final String deviceId;
  List<DocumentEntry> entries = [];
  Future<void> refresh() async {
    entries = await repository.list();
    notifyListeners();
  }

  Future<DocumentEntry> createNotebook({
    required String title,
    required String subject,
    required PaperPattern pattern,
  }) async {
    final book = Notebook.blank(
      id: const Uuid().v4(),
      pageId: const Uuid().v4(),
      title: title.trim().isEmpty ? 'Cuaderno sin título' : title.trim(),
      subject: subject.trim(),
      pattern: pattern,
      now: DateTime.now().toUtc(),
    );
    return add(book);
  }

  Future<DocumentEntry> add(Notebook book) async {
    final revision = Revision(
      id: const Uuid().v4(),
      deviceId: deviceId,
      parentId: null,
      createdAt: DateTime.now().toUtc(),
      notebook: book,
    );
    await repository.commit(revision);
    await refresh();
    return entries.firstWhere((e) => e.headId == revision.id);
  }

  List<DocumentEntry> filtered({String query = '', String subject = ''}) =>
      entries
          .where(
            (e) =>
                (subject.isEmpty || e.notebook.subject == subject) &&
                _normalize(e.notebook.title).contains(_normalize(query)),
          )
          .toList();
  static String _normalize(String text) {
    const accents = 'áéíóúüñ';
    const plain = 'aeiouun';
    var normalized = text.toLowerCase();
    for (var i = 0; i < accents.length; i++) {
      normalized = normalized.replaceAll(accents[i], plain[i]);
    }
    return normalized;
  }
}
