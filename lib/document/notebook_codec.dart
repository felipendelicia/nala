import 'dart:convert';
import 'notebook.dart';
import 'revision.dart';

class NotebookCodec {
  static Map<String, Object> _notebookJson(Notebook book) => {
    'schemaVersion': 1,
    'id': book.id,
    'title': book.title,
    'subject': book.subject,
    if (book.folderId != null) 'folderId': book.folderId!,
    'updatedAt': book.updatedAt.toUtc().toIso8601String(),
    'pages': book.pages.map((p) => p.toJson()).toList(),
  };
  static String encode(Notebook book) => jsonEncode(_notebookJson(book));
  static Notebook decode(String json) =>
      _validated(() => _fromJson(jsonDecode(json) as Map<String, dynamic>));
  static String encodeRevision(Revision revision) => jsonEncode({
    'schemaVersion': 1,
    'id': revision.id,
    'deviceId': revision.deviceId,
    'parentId': revision.parentId,
    'createdAt': revision.createdAt.toUtc().toIso8601String(),
    'notebook': _notebookJson(revision.notebook),
  });
  static Revision decodeRevision(String json) => _validated(() {
    final map = jsonDecode(json) as Map<String, dynamic>;
    _version(map);
    final id = nonEmpty(map['id']);
    final parent = map['parentId'] == null ? null : nonEmpty(map['parentId']);
    if (parent == id) throw const FormatException('Revisión cíclica');
    return Revision(
      id: id,
      deviceId: nonEmpty(map['deviceId']),
      parentId: parent,
      createdAt: DateTime.parse(map['createdAt'] as String).toUtc(),
      notebook: _fromJson(map['notebook'] as Map<String, dynamic>),
    );
  });
  static Notebook _fromJson(Map<String, dynamic> map) {
    _version(map);
    final pages = (map['pages'] as List)
        .map((p) => NotebookPage.fromJson(p as Map<String, dynamic>))
        .toList();
    if (pages.isEmpty) throw const FormatException('Cuaderno sin páginas');
    final pageIds = <String>{};
    final strokeIds = <String>{};
    final commentIds = <String>{};
    for (final page in pages) {
      if (!pageIds.add(page.id)) {
        throw const FormatException('Página duplicada');
      }
      for (final comment in page.comments) {
        if (!commentIds.add(comment.id) ||
            comment.x > page.width ||
            comment.y > page.height) {
          throw const FormatException(
            'Comentario duplicado o fuera de la hoja',
          );
        }
      }
      for (final stroke in page.strokes) {
        if (!strokeIds.add(stroke.id)) {
          throw const FormatException('Trazo duplicado');
        }
      }
    }
    return Notebook(
      id: nonEmpty(map['id']),
      title: nonEmpty(map['title']),
      subject: map['subject'] as String,
      folderId: map['folderId'] == null ? null : nonEmpty(map['folderId']),
      pages: pages,
      updatedAt: DateTime.parse(map['updatedAt'] as String).toUtc(),
    );
  }

  static void _version(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Versión de archivo no compatible');
    }
  }

  static T _validated<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Documento dañado');
    }
  }
}
