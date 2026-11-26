import 'dart:convert';

import 'package:apuntes/account/token_store.dart';
import 'package:apuntes/ai/chat_gpt_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jose/jose.dart';

class _MemoryTokens implements TokenStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  test(
    'autoriza el plan, verifica la identidad y exige un resultado completo',
    () async {
      final key = JsonWebKey.generate('RS256', keyBitLength: 2048);
      final publicKey = JsonWebKey.fromCryptoKeys(
        publicKey: key.cryptoKeyPair.publicKey,
        keyId: key.keyId,
      );
      final store = _MemoryTokens();
      final now = DateTime.utc(2026, 11, 25, 12);
      final claimsTime = now.millisecondsSinceEpoch ~/ 1000;
      Uri? authorization;
      var complete = true, revoked = false, refreshes = 0;
      var browserReturned = false;
      var time = now;
      final client = ChatGptClient(
        tokenStore: store,
        now: () => time,
        httpClient: MockClient((request) async {
          switch (request.url.path) {
            case '/api/accounts/oauth/token':
              final body = request.bodyFields;
              expect(body['client_id'], 'oaiapp_nala_fixture');
              expect(body['resource'], 'https://api.openai.com/v1');
              if (body['grant_type'] == 'refresh_token') {
                expect(body['refresh_token'], 'refresh-test-0');
                refreshes++;
                return http.Response(
                  jsonEncode({
                    'access_token': 'access-test-1',
                    'refresh_token': 'refresh-test-1',
                    'token_type': 'Bearer',
                    'expires_in': 3600,
                    'scope': 'openid resource.invoke chatgpt.tokens.use.direct',
                  }),
                  200,
                );
              }
              expect(body['grant_type'], 'authorization_code');
              expect(browserReturned, isTrue);
              expect(body['code'], 'auth-code-test');
              final query = authorization!.queryParameters;
              expect(body['redirect_uri'], query['redirect_uri']);
              final challenge = sha256.convert(
                utf8.encode(body['code_verifier']!),
              );
              expect(
                base64Url.encode(challenge.bytes).replaceAll('=', ''),
                query['code_challenge'],
              );
              final builder = JsonWebSignatureBuilder()
                ..jsonContent = {
                  'iss': 'https://auth.openai.com',
                  'sub': 'subject-test',
                  'aud': 'oaiapp_nala_fixture',
                  'nonce': query['nonce']!,
                  'iat': claimsTime,
                  'exp': claimsTime + 3600,
                  'email': 'alumno@example.com',
                }
                ..addRecipient(key, algorithm: 'RS256');
              return http.Response(
                jsonEncode({
                  'access_token': 'access-test-0',
                  'refresh_token': 'refresh-test-0',
                  'token_type': 'Bearer',
                  'expires_in': 3600,
                  'scope': 'openid resource.invoke chatgpt.tokens.use.direct',
                  'id_token': builder.build().toCompactSerialization(),
                }),
                200,
              );
            case '/.well-known/jwks.json':
              return http.Response(
                jsonEncode({
                  'keys': [publicKey.toJson()],
                }),
                200,
              );
            case '/v1/models':
              expect(request.headers['authorization'], 'Bearer access-test-1');
              return http.Response(
                jsonEncode({
                  'models': [
                    {
                      'slug': 'oculto',
                      'display_name': 'Oculto',
                      'visibility': 'hidden',
                    },
                    {
                      'slug': 'gpt-clase',
                      'display_name': 'GPT Clase',
                      'visibility': 'list',
                    },
                  ],
                }),
                200,
              );
            case '/v1/responses':
              expect(request.headers['authorization'], 'Bearer access-test-1');
              final body = jsonDecode(request.body) as Map;
              expect(body['model'], 'gpt-clase');
              expect(body['store'], false);
              expect(body['stream'], true);
              expect(body['instructions'], 'Corregir el texto.');
              expect(body['input'][0]['content'][0]['text'], 'apuntes clase');
              return http.Response(
                'data: {"type":"response.output_text.delta","delta":"Apuntes de clase."}\r\n\r\n'
                '${complete ? 'data: {"type":"response.completed"}\r\n\r\n' : ''}',
                200,
                headers: {'content-type': 'text/event-stream; charset=utf-8'},
              );
            case '/.well-known/openid-configuration':
              return http.Response(
                jsonEncode({
                  'issuer': 'https://auth.openai.com',
                  'revocation_endpoint':
                      'https://auth.openai.com/api/accounts/oauth/revoke',
                }),
                200,
              );
            case '/api/accounts/oauth/revoke':
              expect(request.bodyFields['client_id'], 'oaiapp_nala_fixture');
              expect(request.bodyFields['token'], 'refresh-test-1');
              revoked = true;
              return http.Response('', 200);
          }
          throw StateError('Unexpected path ${request.url.path}');
        }),
      );
      addTearDown(client.dispose);

      await client.signIn(
        (url) async {
          authorization = url;
          final query = url.queryParameters;
          expect(url.host, 'auth.openai.com');
          expect(query['client_id'], 'dynamic_agent_client');
          expect(query['agent_name_hint'], 'Nala');
          expect(query['ext_agent_host_id'], startsWith('urn:uuid:'));
          expect(query['scope'], contains('chatgpt.tokens.use.direct'));
          final redirect = Uri.parse(query['redirect_uri']!);
          expect(redirect.host, '127.0.0.1');
          final callback = await http.get(
            redirect.replace(
              queryParameters: {
                'state': query['state'],
                'code': 'auth-code-test',
                'client_id': 'oaiapp_nala_fixture',
              },
            ),
          );
          expect(callback.statusCode, 200);
          expect(callback.headers['referrer-policy'], 'no-referrer');
          expect(callback.body, contains('Autorización recibida'));
          expect(callback.body, isNot(contains('auth-code-test')));
          return true;
        },
        onBrowserReturn: () async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          browserReturned = true;
        },
      );
      expect(client.activeAccount?.email, 'alumno@example.com');
      expect(client.connected, isTrue);

      time = time.add(const Duration(hours: 1));
      final models = await Future.wait([
        client.listModels(),
        client.listModels(),
      ]);
      expect(refreshes, 1);
      expect(models.first.single.displayName, 'GPT Clase');
      Future<String> respond() => client.respond(
        model: models.first.single.slug,
        instructions: 'Corregir el texto.',
        text: 'apuntes clase',
      );
      expect(await respond(), 'Apuntes de clase.');
      complete = false;
      await expectLater(respond(), throwsA(isA<ChatGptException>()));

      expect(await client.signOut(), isTrue);
      expect(revoked, isTrue);
      expect(client.connected, isFalse);
      expect(client.accounts.single.id, 'oaiapp_nala_fixture');
      expect(store.values.values.single, isNot(contains('refresh-test-1')));
    },
  );

  test('la cancelación del navegador termina sin canjear un código', () async {
    final client = ChatGptClient(
      tokenStore: _MemoryTokens(),
      httpClient: MockClient((request) async {
        fail('No debe abrirse una conexión con ${request.url.host}.');
      }),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.signIn((url) async {
        final callback = Uri.parse(url.queryParameters['redirect_uri']!);
        final invalid = await http.get(
          callback.replace(queryParameters: {'state': 'estado inválido'}),
        );
        expect(invalid.statusCode, 400);
        final declined = await http.get(
          callback.replace(
            queryParameters: {
              'state': url.queryParameters['state']!,
              'error': 'access_denied',
            },
          ),
        );
        expect(declined.statusCode, 200);
        expect(declined.body, contains('Solicitud cancelada'));
        expect(declined.body, isNot(contains('Autorización recibida')));
        return true;
      }),
      throwsA(
        isA<ChatGptException>().having(
          (error) => error.code,
          'code',
          'access_denied',
        ),
      ),
    );
    expect(client.connected, isFalse);
  });
}
