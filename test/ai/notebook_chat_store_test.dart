import 'dart:io';

import 'package:apuntes/ai/notebook_chat_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nala-notebook-chats-');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('reabrir conserva las conversaciones de cada apunte', () async {
    final store = NotebookChatStore(root.path);
    final now = DateTime.utc(2026, 11, 25, 20);
    await store.save(
      'álgebra',
      NotebookChat(
        id: 'uno',
        title: 'Eliminación de Gauss',
        updatedAt: now,
        messages: [
          NotebookChatMessage(isUser: true, text: '¿Cómo despejo x?'),
          NotebookChatMessage(
            isUser: false,
            text: 'Restá la segunda fila.',
            pageIds: ['hoja-4'],
          ),
        ],
      ),
    );
    await store.save(
      'física',
      NotebookChat(id: 'uno', title: 'Energía', updatedAt: now),
    );

    final reopened = NotebookChatStore(root.path);
    final restored = (await reopened.list('álgebra')).single;
    expect(restored.title, 'Eliminación de Gauss');
    expect(restored.updatedAt, DateTime.utc(2026, 11, 25, 20));
    expect(restored.messages.map((message) => message.isUser), [true, false]);
    expect(restored.messages.first.text, '¿Cómo despejo x?');
    expect(restored.messages.last.text, 'Restá la segunda fila.');
    expect(restored.messages.last.pageIds, ['hoja-4']);
    expect((await reopened.list('física')).single.title, 'Energía');
    expect(await reopened.list('química'), isEmpty);
  });

  test('guardados superpuestos preservan chats distintos y su orden', () async {
    final store = NotebookChatStore(root.path);
    final otherView = NotebookChatStore(root.path);
    final first = NotebookChat(
      id: 'uno',
      title: 'Primer borrador',
      updatedAt: DateTime.utc(2026, 11, 24),
    );

    await Future.wait([
      store.save('historia', first),
      otherView.save(
        'historia',
        NotebookChat(
          id: 'dos',
          title: 'Revolución Industrial',
          updatedAt: DateTime.utc(2026, 11, 25),
        ),
      ),
      store.save(
        'historia',
        first.copyWith(
          title: 'Revolución de Mayo',
          updatedAt: DateTime.utc(2026, 11, 26),
        ),
      ),
    ]);

    final restored = await NotebookChatStore(root.path).list('historia');
    expect(restored.map((chat) => chat.id), ['uno', 'dos']);
    expect(restored.map((chat) => chat.title), [
      'Revolución de Mayo',
      'Revolución Industrial',
    ]);
  });
}
