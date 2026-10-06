import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:url_launcher/url_launcher.dart';
import 'auth_service.dart';
import 'token_store.dart';

class LinuxAuthService implements AuthService {
  LinuxAuthService({
    required this.clientId,
    this.clientSecret = '',
    TokenStore? tokenStore,
    http.Client? client,
    Future<bool> Function(Uri)? openBrowser,
  }) : tokenStore = tokenStore ?? const SecureTokenStore(),
       _http = client ?? http.Client(),
       openBrowser =
           openBrowser ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));
  final String clientId, clientSecret;
  final TokenStore tokenStore;
  final http.Client _http;
  final Future<bool> Function(Uri) openBrowser;
  @override
  GoogleAccount? current;
  @override
  bool secureStorageAvailable = true;
  oauth2.Credentials? _credentials;
  HttpServer? _server;
  Completer<void>? _cancel;
  bool _closed = false;
  Future<void>? _refreshing;

  @override
  Future<GoogleAccount?> restore() async {
    try {
      final value = await tokenStore.read();
      if (value == null) return null;
      final json = jsonDecode(value) as Map<String, dynamic>;
      if (json['clientId'] != clientId) return null;
      _credentials = oauth2.Credentials.fromJson(json['credentials'] as String);
      current = GoogleAccount.fromJson(json['account'] as Map<String, dynamic>);
      return current;
    } catch (_) {
      secureStorageAvailable = false;
      return null;
    }
  }

  Future<void> _persist() async {
    if (_credentials == null || current == null || _closed) return;
    try {
      await tokenStore.write(
        jsonEncode({
          'clientId': clientId,
          'account': current!.toJson(),
          'credentials': _credentials!.toJson(),
        }),
      );
    } catch (_) {
      secureStorageAvailable = false;
    }
  }

  Future<T> _wait<T>(Future<T> future, Completer<void> cancelled) => Future.any(
    [future, cancelled.future.then<T>((_) => throw const AuthCancelled())],
  );

  @override
  Future<GoogleAccount> signIn() async {
    if (_closed || _cancel != null) throw const AuthCancelled();
    final cancelled = _cancel = Completer<void>();
    final callback = Completer<Map<String, String>>();
    final state = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    ).replaceAll('=', '');
    oauth2.AuthorizationCodeGrant? grant;
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      if (cancelled.isCompleted) throw const AuthCancelled();
      final redirect = Uri.parse(
        'http://127.0.0.1:${server.port}/oauth2callback',
      );
      server.listen((request) async {
        final valid =
            request.method == 'GET' &&
            request.uri.path == redirect.path &&
            request.uri.queryParameters['state'] == state &&
            !callback.isCompleted;
        request.response.statusCode = valid ? 200 : 400;
        request.response.headers.contentType = ContentType.text;
        request.response.write(
          valid
              ? 'Ya podés volver a Nala.'
              : 'Esta respuesta no corresponde a la conexión de Nala.',
        );
        await request.response.close();
        if (valid && !callback.isCompleted) {
          callback.complete(request.uri.queryParameters);
        }
      });
      grant = oauth2.AuthorizationCodeGrant(
        clientId,
        Uri.parse('https://accounts.google.com/o/oauth2/v2/auth'),
        Uri.parse('https://oauth2.googleapis.com/token'),
        secret: clientSecret.isEmpty ? null : clientSecret,
        basicAuth: false,
        httpClient: _BorrowedClient(_http),
      );
      final authorization = grant.getAuthorizationUrl(
        redirect,
        scopes: ['openid', 'email', driveScope],
        state: state,
      );
      final url = authorization.replace(
        queryParameters: {
          ...authorization.queryParameters,
          'access_type': 'offline',
          'prompt': 'consent',
        },
      );
      if (!await _wait(openBrowser(url), cancelled)) {
        throw StateError('No se pudo abrir el navegador.');
      }
      final response = await _wait(
        callback.future.timeout(const Duration(minutes: 3)),
        cancelled,
      );
      if (response['error'] == 'access_denied') throw const AuthCancelled();
      final candidate = await _wait(
        grant
            .handleAuthorizationResponse(response)
            .timeout(const Duration(seconds: 30)),
        cancelled,
      );
      try {
        if (candidate.credentials.scopes?.contains(driveScope) != true) {
          throw const AuthRequired();
        }
        final profile = await _wait(
          _http
              .get(
                Uri.parse('https://openidconnect.googleapis.com/v1/userinfo'),
                headers: {
                  'Authorization':
                      'Bearer ${candidate.credentials.accessToken}',
                },
              )
              .timeout(const Duration(seconds: 30)),
          cancelled,
        );
        if (profile.statusCode != 200) throw const AuthRequired();
        final data = jsonDecode(profile.body) as Map<String, dynamic>;
        final account = GoogleAccount.fromJson({
          'id': data['sub'],
          'email': data['email'],
        });
        if (cancelled.isCompleted || _closed) throw const AuthCancelled();
        current = account;
        _credentials = candidate.credentials;
        await _persist();
        return account;
      } finally {
        candidate.close();
      }
    } finally {
      await server?.close(force: true);
      grant?.close();
      if (identical(_cancel, cancelled)) {
        _cancel = null;
        _server = null;
      }
    }
  }

  Future<void> _refresh() async {
    final credentials = _credentials, account = current;
    try {
      final refreshed = await credentials!
          .refresh(
            identifier: clientId,
            secret: clientSecret.isEmpty ? null : clientSecret,
            basicAuth: false,
            httpClient: _BorrowedClient(_http),
          )
          .timeout(const Duration(seconds: 30));
      if (_closed ||
          !identical(current, account) ||
          !identical(_credentials, credentials)) {
        throw const AuthRequired();
      }
      _credentials = refreshed;
      await _persist();
    } on oauth2.AuthorizationException {
      throw const AuthRequired();
    }
  }

  @override
  Future<Map<String, String>> authorizationHeaders({
    bool forceRefresh = false,
  }) async {
    final credentials = _credentials;
    final account = current;
    if (credentials == null || current == null || _closed) {
      throw const AuthRequired();
    }
    if (forceRefresh ||
        (credentials.expiration != null &&
            DateTime.now()
                .add(const Duration(seconds: 30))
                .isAfter(credentials.expiration!))) {
      if (!credentials.canRefresh) throw const AuthRequired();
      await (_refreshing ??= _refresh().whenComplete(() => _refreshing = null));
    }
    if (_closed || !identical(current, account)) throw const AuthRequired();
    return {'Authorization': 'Bearer ${_credentials!.accessToken}'};
  }

  @override
  Future<void> cancelSignIn() async {
    final pending = _cancel;
    if (pending != null && !pending.isCompleted) pending.complete();
    await _server?.close(force: true);
  }

  @override
  Future<void> signOut() async {
    await cancelSignIn();
    current = null;
    _credentials = null;
    try {
      await tokenStore.delete();
    } catch (_) {
      secureStorageAvailable = false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(cancelSignIn());
    _http.close();
  }
}

class _BorrowedClient extends http.BaseClient {
  _BorrowedClient(this.client);
  final http.Client client;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      client.send(request);
  @override
  void close() {}
}
