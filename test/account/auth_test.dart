import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:apuntes/account/auth_service.dart';
import 'package:apuntes/account/linux_auth_service.dart';
import '../support/fake_auth_service.dart';

void main() {
  test(
    'una renovación tardía no devuelve credenciales después de salir',
    () async {
      final store = FakeTokenStore()
        ..value = jsonEncode({
          'clientId': 'fixture-client',
          'account': {'id': 'old', 'email': 'old@example.invalid'},
          'credentials': oauth2.Credentials(
            'old-token',
            refreshToken: 'old-refresh',
            tokenEndpoint: Uri.parse('https://oauth2.googleapis.com/token'),
          ).toJson(),
        });
      final started = Completer<void>(), response = Completer<http.Response>();
      final auth = LinuxAuthService(
        clientId: 'fixture-client',
        tokenStore: store,
        client: MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      await auth.restore();
      final pending = auth.authorizationHeaders(forceRefresh: true);
      final expectation = expectLater(pending, throwsA(isA<AuthRequired>()));
      await started.future;
      await auth.signOut();
      // Another cached account may be restored while the previous refresh waits.
      store.value = jsonEncode({
        'clientId': 'fixture-client',
        'account': {'id': 'new', 'email': 'new@example.invalid'},
        'credentials': oauth2.Credentials('new-token').toJson(),
      });
      await auth.restore();
      response.complete(
        http.Response(
          '{"access_token":"stale-token","token_type":"Bearer"}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectation;
      expect(
        (await auth.authorizationHeaders())['Authorization'],
        'Bearer new-token',
      );
      auth.dispose();
    },
  );
  test(
    'OAuth Linux usa PKCE, verifica state y restaura la misma cuenta',
    () async {
      final store = FakeTokenStore();
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/token')) {
          return http.Response(
            jsonEncode({
              'access_token': 'fixture-access',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'refresh_token': 'fixture-refresh',
              'scope': 'openid email $driveScope',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'sub': 'student-id', 'email': 'student@example.invalid'}),
          200,
        );
      });
      final auth = LinuxAuthService(
        clientId: 'fixture-client.apps.googleusercontent.com',
        tokenStore: store,
        client: client,
        openBrowser: (url) async {
          expect(url.queryParameters['code_challenge_method'], 'S256');
          expect(url.queryParameters['code_challenge'], isNotEmpty);
          expect(url.queryParameters['access_type'], 'offline');
          final callback = Uri.parse(url.queryParameters['redirect_uri']!);
          expect(callback.host, '127.0.0.1');
          final wrong = await http.get(
            callback.replace(
              queryParameters: {'code': 'fixture-code', 'state': 'incorrect'},
            ),
          );
          expect(wrong.statusCode, 400);
          final correct = await http.get(
            callback.replace(
              queryParameters: {
                'code': 'fixture-code',
                'state': url.queryParameters['state']!,
              },
            ),
          );
          expect(correct.statusCode, 200);
          return true;
        },
      );
      final account = await auth.signIn();
      expect(account.id, 'student-id');
      expect(account.email, 'student@example.invalid');
      final tokenRequest = requests.singleWhere(
        (r) => r.url.path.endsWith('/token'),
      );
      expect(
        Uri.splitQueryString(tokenRequest.body)['code_verifier'],
        isNotEmpty,
      );
      expect(Uri.splitQueryString(tokenRequest.body)['code'], 'fixture-code');
      expect(store.value, isNotNull);
      final restored = LinuxAuthService(
        clientId: 'fixture-client.apps.googleusercontent.com',
        tokenStore: store,
        client: MockClient((_) async => http.Response('', 500)),
        openBrowser: (_) async => false,
      );
      expect((await restored.restore())!.id, account.id);
      expect(
        (await restored.authorizationHeaders())['Authorization'],
        'Bearer fixture-access',
      );
      await restored.signOut();
      expect(store.value, isNull);
      auth.dispose();
      restored.dispose();
    },
  );
  test(
    'cancelar cierra el callback; llavero ausente conserva sólo la sesión en memoria',
    () async {
      final opened = Completer<void>();
      Uri? redirect;
      final auth = LinuxAuthService(
        clientId: 'fixture-client.apps.googleusercontent.com',
        tokenStore: FakeTokenStore(),
        openBrowser: (url) async {
          redirect = Uri.parse(url.queryParameters['redirect_uri']!);
          opened.complete();
          return true;
        },
      );
      final signingIn = auth.signIn();
      final cancelled = expectLater(signingIn, throwsA(isA<AuthCancelled>()));
      await opened.future;
      await auth.cancelSignIn();
      await cancelled;
      expect(auth.current, isNull);
      await expectLater(
        http.get(redirect!),
        throwsA(isA<http.ClientException>()),
      );
      auth.dispose();
      final unavailable = FakeTokenStore()..unavailable = true;
      final memory = LinuxAuthService(
        clientId: 'fixture-client.apps.googleusercontent.com',
        tokenStore: unavailable,
        client: MockClient(
          (request) async => request.url.path.endsWith('/token')
              ? http.Response(
                  jsonEncode({
                    'access_token': 'fixture-access',
                    'token_type': 'Bearer',
                    'expires_in': 3600,
                    'refresh_token': 'fixture-refresh',
                  }),
                  200,
                  headers: {'content-type': 'application/json'},
                )
              : http.Response(
                  jsonEncode({
                    'sub': 'memory-account',
                    'email': 'memory@example.invalid',
                  }),
                  200,
                ),
        ),
        openBrowser: (url) async {
          final response = await http.get(
            Uri.parse(url.queryParameters['redirect_uri']!).replace(
              queryParameters: {
                'code': 'fixture-code',
                'state': url.queryParameters['state']!,
              },
            ),
          );
          return response.statusCode == 200;
        },
      );
      expect(await memory.restore(), isNull);
      expect((await memory.signIn()).id, 'memory-account');
      expect(memory.secureStorageAvailable, isFalse);
      expect(unavailable.value, isNull);
      expect(
        (await memory.authorizationHeaders())['Authorization'],
        'Bearer fixture-access',
      );
      memory.dispose();
    },
  );
}
