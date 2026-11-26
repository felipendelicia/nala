import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class NotebookChatMessage {
  NotebookChatMessage({
    required this.isUser,
    required this.text,
    List<String> pageIds = const [],
  }) : pageIds = List.unmodifiable(pageIds);

  final bool isUser;
  final String text;
  final List<String> pageIds;

  factory NotebookChatMessage._fromJson(Map<String, dynamic> json) =>
      NotebookChatMessage(
        isUser: json['isUser'] as bool,
        text: json['text'] as String,
        pageIds: (json['pageIds'] as List? ?? []).cast<String>(),
      );

  Map<String, Object> _toJson() => {
    'isUser': isUser,
    'text': text,
    if (pageIds.isNotEmpty) 'pageIds': pageIds,
  };
}

class NotebookChat {
  NotebookChat({
    required this.id,
    required this.title,
    required DateTime updatedAt,
    List<NotebookChatMessage> messages = const [],
  }) : updatedAt = updatedAt.toUtc(),
       messages = List.unmodifiable(messages);

  final String id;
  final String title;
  final DateTime updatedAt;
  final List<NotebookChatMessage> messages;

  NotebookChat copyWith({
    String? title,
    DateTime? updatedAt,
    List<NotebookChatMessage>? messages,
  }) => NotebookChat(
    id: id,
    title: title ?? this.title,
    updatedAt: updatedAt ?? this.updatedAt,
    messages: messages ?? this.messages,
  );

  factory NotebookChat._fromJson(Map<String, dynamic> json) => NotebookChat(
    id: json['id'] as String,
    title: json['title'] as String,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    messages: (json['messages'] as List)
        .cast<Map<String, dynamic>>()
        .map(NotebookChatMessage._fromJson)
        .toList(),
  );

  Map<String, Object> _toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((message) => message._toJson()).toList(),
  };
}

/// Stores conversation history independently of page edits and editor undo.
class NotebookChatStore {
  NotebookChatStore(String root)
    : _directory = p.normalize(p.absolute(root, 'local', 'chatgpt'));

  final String _directory;
  static final _pendingWrites = <String, Future<void>>{};

  static String _fileKey(String id) =>
      sha256.convert(utf8.encode(id)).toString();

  Directory _notebookDirectory(String notebookId) =>
      Directory(p.join(_directory, _fileKey(notebookId)));

  Future<List<NotebookChat>> list(String notebookId) async {
    final directory = _notebookDirectory(notebookId);
    await _pendingWrites[directory.path];
    if (!await directory.exists()) return const [];
    final chats = <NotebookChat>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File && p.extension(entry.path) == '.json') {
        final data = jsonDecode(await entry.readAsString());
        chats.add(NotebookChat._fromJson(data as Map<String, dynamic>));
      }
    }
    chats.sort((first, second) {
      final time = second.updatedAt.compareTo(first.updatedAt);
      return time == 0 ? first.id.compareTo(second.id) : time;
    });
    return List.unmodifiable(chats);
  }

  Future<void> save(String notebookId, NotebookChat chat) {
    final directory = _notebookDirectory(notebookId);
    final previous = _pendingWrites[directory.path] ?? Future<void>.value();
    final write = previous.then((_) => _write(directory, chat));
    final pending = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pendingWrites[directory.path] = pending;
    return write.whenComplete(() {
      if (identical(_pendingWrites[directory.path], pending)) {
        _pendingWrites.remove(directory.path);
      }
    });
  }

  Future<void> _write(Directory directory, NotebookChat chat) async {
    await directory.create(recursive: true);
    final destination = p.join(directory.path, '${_fileKey(chat.id)}.json');
    final staged = File(p.join(directory.path, '${const Uuid().v4()}.tmp'));
    try {
      await staged.writeAsString(jsonEncode(chat._toJson()), flush: true);
      await staged.rename(destination);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }
}
