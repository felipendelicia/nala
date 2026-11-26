import 'dart:convert';
import 'dart:typed_data';

import 'package:apuntes/account/token_store.dart';
import 'package:apuntes/ai/chat_gpt_client.dart';
import 'package:apuntes/ai/notebook_chat_store.dart';
import 'package:apuntes/ai/notebook_study_service.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/document/page_comment.dart';
import 'package:apuntes/pdf/pdf_export_service.dart';
import 'package:apuntes/pdf/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Notebook notebook;
  late _PdfProbe exporter;
  late List<Map<String, dynamic>> requests;
  late String responseText;
  late bool rejectFirstModel;
  late NotebookStudyService service;

  setUp(() {
    notebook = Notebook(
      id: 'notebook',
      title: 'Álgebra',
      subject: '',
      updatedAt: DateTime.utc(2026),
      pages: [_page('first'), _page('skipped'), _page('page/(three)')],
    );
    exporter = _PdfProbe();
    requests = [];
    responseText = 'Resultado';
    rejectFirstModel = false;
    final client = ChatGptClient(
      tokenStore: _SignedInStore(),
      now: () => DateTime.utc(2026),
      httpClient: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer fixture');
        if (request.url.path == '/v1/models') {
          return http.Response(
            jsonEncode({
              'models': [
                {
                  'slug': 'first-model',
                  'display_name': 'Primero',
                  'visibility': 'list',
                },
                {
                  'slug': 'second-model',
                  'display_name': 'Segundo',
                  'visibility': 'list',
                },
              ],
            }),
            200,
          );
        }
        expect(request.url.path, '/v1/responses');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        if (rejectFirstModel && body['model'] == 'first-model') {
          return http.Response(
            '{"error":{"code":"subscription_sharing_unsupported_capability"}}',
            400,
          );
        }
        final delta = jsonEncode({
          'type': 'response.output_text.delta',
          'delta': responseText,
        });
        return http.Response(
          'data: $delta\n\ndata: {"type":"response.completed"}\n\n',
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      }),
    );
    addTearDown(client.dispose);
    service = NotebookStudyService(client: client, exporter: exporter);
  });

  test(
    'ask exports only selected sheets and keeps numbered citations stable',
    () async {
      responseText =
          'La fórmula está en [Hoja 3](nala-page:3). '
          '[Hoja 2](nala-page:2)';

      final answer = await service.ask(
        notebook: notebook,
        pageIds: ['page/(three)', 'first'],
        messages: [
          NotebookChatMessage(isUser: true, text: '¿Qué fórmula usan?'),
          NotebookChatMessage(isUser: false, text: 'La identidad notable.'),
          NotebookChatMessage(isUser: true, text: '¿Dónde aparece?'),
        ],
      );

      expect(exporter.snapshot.pages.map((p) => p.id), [
        'first',
        'page/(three)',
      ]);
      expect(exporter.snapshot.pages.every((p) => p.comments.isEmpty), isTrue);
      final request = requests.single;
      expect(request['store'], isFalse);
      expect(request['stream'], isTrue);
      final input = request['input'] as List;
      expect(input.take(2), [
        {'role': 'user', 'content': '¿Qué fórmula usan?'},
        {'role': 'assistant', 'content': 'La identidad notable.'},
      ]);
      final parts = input.last['content'] as List;
      expect(parts.first['text'], contains('1, 3'));
      expect(parts.first['text'], contains('¿Dónde aparece?'));
      expect(parts.last['file_data'], 'data:application/pdf;base64,AQID');
      expect(
        answer,
        'La fórmula está en [Hoja 3](nala-page:page%2F%28three%29).',
      );
    },
  );

  test('ask retries with a model that accepts the attached sheets', () async {
    rejectFirstModel = true;
    responseText = 'La respuesta es **una identidad notable**.';

    final answer = await service.ask(
      notebook: notebook,
      pageIds: ['first'],
      messages: [NotebookChatMessage(isUser: true, text: '¿Qué fórmula usan?')],
    );

    expect(answer, 'La respuesta es **una identidad notable**.');
    expect(requests.map((r) => r['model']), ['first-model', 'second-model']);
    expect(exporter.exports, 1);
  });

  test('cancelling PDF unlock leaves the notebook out of inference', () async {
    exporter.locked = true;

    await expectLater(
      service.ask(
        notebook: notebook,
        pageIds: ['first'],
        messages: [NotebookChatMessage(isUser: true, text: '¿Dónde aparece?')],
        unlock: (assetId) async {
          expect(assetId, 'pdf-resource');
          return false;
        },
      ),
      throwsA(isA<ChatGptException>()),
    );

    expect(requests, isEmpty);
  });
}

NotebookPage _page(String id) => NotebookPage(
  id: id,
  width: 100,
  height: 150,
  background: const PageBackground.paper(PaperPattern.blank),
  comments: [
    PageComment(
      id: 'comment',
      x: 10,
      y: 20,
      text: 'Comentario',
      createdAt: DateTime.utc(2026),
    ),
  ],
);

class _PdfProbe extends PdfExportService {
  _PdfProbe() : super(PdfService(assets: FileAssetStore('unused')));

  late Notebook snapshot;
  bool locked = false;
  int exports = 0;

  @override
  Future<Uint8List> export(Notebook notebook) async {
    snapshot = notebook;
    exports++;
    if (locked) throw const PdfExportPasswordRequired('pdf-resource');
    return Uint8List.fromList([1, 2, 3]);
  }
}

class _SignedInStore implements TokenStore {
  @override
  Future<String?> read(String key) async => jsonEncode({
    'hostId': 'notebook-host',
    'activeId': 'account',
    'accounts': [
      {
        'id': 'account',
        'subject': 'subject',
        'email': 'alumno@example.com',
        'tokens': {
          'accessToken': 'fixture',
          'scopes': ['chatgpt.tokens.use.direct'],
          'expiresAt': '2027-01-01T00:00:00Z',
        },
      },
    ],
  });

  @override
  Future<void> write(String key, String value) => throw UnimplementedError();

  @override
  Future<void> delete(String key) => throw UnimplementedError();
}
