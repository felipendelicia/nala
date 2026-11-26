part of 'chat_gpt_client.dart';

class _ChatGptOAuth {
  _ChatGptOAuth(this._http, this._now);

  final http.Client _http;
  final DateTime Function() _now;
  static const _callbackPath = '/auth/callback';
  static const _dynamicId = 'dynamic_agent_client';
  static final _tokenEndpoint = Uri.parse('$_issuer/api/accounts/oauth/token');
  JsonWebKeyStore? _keys;
  DateTime? _keysFetchedAt;
  void Function()? _cancelSignIn;

  Future<_AccountRecord> signIn(
    Future<bool> Function(Uri) openBrowser, {
    required String hostId,
    _AccountRecord? existing,
    FutureOr<void> Function()? onBrowserReturn,
  }) async {
    final state = _randomUrlString(), nonce = _randomUrlString();
    final verifier = _randomUrlString();
    final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } on SocketException {
      throw const ChatGptException(
        'No se pudo iniciar la conexión local para volver del navegador.',
      );
    }
    final redirect = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: _callbackPath,
    );
    final callback = Completer<_BrowserGrant?>();
    var handled = false;
    _cancelSignIn = () {
      if (!callback.isCompleted) callback.complete(null);
      unawaited(server.close(force: true));
    };
    server.listen((request) {
      final params = request.uri.queryParametersAll;
      final valid =
          request.method == 'GET' &&
          request.uri.path == _callbackPath &&
          params['state']?.singleOrNull == state &&
          !handled &&
          !callback.isCompleted;
      if (valid) handled = true;
      final grant = valid ? _BrowserGrant.read(params, existing?.id) : null;
      final response = request.response
        ..statusCode = valid ? HttpStatus.ok : HttpStatus.badRequest
        ..persistentConnection = false
        ..headers.contentType = ContentType.html
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..headers.set('referrer-policy', 'no-referrer');
      response.write(_browserReturnPage(grant));
      // A browser navigating away must not prevent Nala from using the grant.
      unawaited(response.close().then<void>((_) {}, onError: (Object _) {}));
      if (grant != null) callback.complete(grant);
    });
    final authorize = Uri.parse('$_issuer/api/accounts/authorize').replace(
      queryParameters: {
        'client_id': existing?.id ?? _dynamicId,
        if (existing == null) 'agent_name_hint': 'Nala',
        'ext_agent_host_id': hostId,
        'id_token_hint': ?existing?.tokens?.idToken,
        if (existing != null && existing.email.isNotEmpty)
          'login_hint': existing.email,
        if (existing?.tokens case final tokens?)
          if (!tokens.scopes.contains(_directScope)) 'prompt': 'consent',
        'response_type': 'code',
        'redirect_uri': redirect.toString(),
        'scope': _scopes,
        'resource': _resource,
        'state': state,
        'nonce': nonce,
        'code_challenge_method': 'S256',
        'code_challenge': _base64Url(
          sha256.convert(utf8.encode(verifier)).bytes,
        ),
      },
    );
    _BrowserGrant? result;
    try {
      if (!await openBrowser(authorize)) {
        throw const ChatGptException(
          'No se pudo abrir el navegador para iniciar sesión.',
        );
      }
      result = await callback.future.timeout(const Duration(minutes: 5));
    } on TimeoutException {
      throw const ChatGptException(
        'Venció el tiempo para iniciar sesión. Volvé a intentarlo.',
      );
    } finally {
      _cancelSignIn = null;
      await server.close(force: result == null);
    }
    if (result == null) {
      throw const ChatGptException('No se autorizó la conexión con ChatGPT.');
    }
    if (result.error case final error?) throw error;
    await onBrowserReturn?.call();
    final clientId = result.clientId!;
    final tokens = await _requestTokens({
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'code': result.code!,
      'code_verifier': verifier,
      'redirect_uri': redirect.toString(),
      'resource': _resource,
    });
    final claims = await _verifyIdentity(
      tokens,
      clientId,
      nonce: nonce,
      subject: existing?.subject,
    );
    return _AccountRecord(
      id: clientId,
      subject: claims.subject!,
      email: claims['email'] is String
          ? claims['email'] as String
          : existing?.email ?? '',
      tokens: tokens,
    );
  }

  void cancel() => _cancelSignIn?.call();

  Future<_AccountRecord> refresh(_AccountRecord record) async {
    final previous = record.tokens!;
    final refreshToken = previous.refreshToken;
    if (refreshToken == null) {
      throw const ChatGptException(
        'La sesión de ChatGPT venció. Volvé a iniciar sesión.',
        code: 'invalid_refresh_token',
      );
    }
    final next = await _requestTokens({
      'grant_type': 'refresh_token',
      'client_id': record.id,
      'refresh_token': refreshToken,
      'resource': _resource,
    }, previousScopes: previous.scopes);
    if (next.idToken != null) {
      await _verifyIdentity(next, record.id, subject: record.subject);
    }
    return _AccountRecord(
      id: record.id,
      subject: record.subject,
      email: record.email,
      tokens: _Tokens(
        accessToken: next.accessToken,
        refreshToken: next.refreshToken ?? previous.refreshToken,
        idToken: next.idToken ?? previous.idToken,
        scopes: next.scopes,
        expiresAt: next.expiresAt,
      ),
    );
  }

  Future<bool> revoke(_AccountRecord record) async {
    final refreshToken = record.tokens?.refreshToken;
    if (refreshToken == null) return true;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final discovery = await _jsonGet(
          Uri.parse('$_issuer/.well-known/openid-configuration'),
        );
        final endpoint = Uri.tryParse(
          discovery['revocation_endpoint'] as String? ?? '',
        );
        if (discovery['issuer'] != _issuer ||
            endpoint == null ||
            endpoint.origin != _issuer ||
            endpoint.userInfo.isNotEmpty) {
          return false;
        }
        final response = await _send(
          'POST',
          endpoint,
          form: {
            'token': refreshToken,
            'token_type_hint': 'refresh_token',
            'client_id': record.id,
          },
        );
        if (response.statusCode == 200) return true;
        if (response.statusCode < 500) return false;
      } on ChatGptException catch (error) {
        if (error.statusCode != null && error.statusCode! < 500) return false;
      } on FormatException {
        return false;
      } on StateError {
        return false;
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 250 << attempt));
      }
    }
    return false;
  }

  Future<_Tokens> _requestTokens(
    Map<String, String> form, {
    Set<String>? previousScopes,
  }) async {
    final response = await _send('POST', _tokenEndpoint, form: form);
    if (response.statusCode != 200) throw _httpError(response);
    try {
      final data = _jsonObject(jsonDecode(utf8.decode(response.bodyBytes)));
      final lifetime = data['expires_in'];
      final accessToken = data['access_token'];
      if (accessToken is! String ||
          accessToken.isEmpty ||
          lifetime is! int ||
          lifetime <= 0 ||
          (data['token_type'] as String?)?.toLowerCase() != 'bearer') {
        throw const FormatException('Token response');
      }
      final scope = data['scope'] as String?;
      return _Tokens(
        accessToken: accessToken,
        refreshToken: data['refresh_token'] as String?,
        idToken: data['id_token'] as String?,
        scopes: scope == null
            ? previousScopes ?? {}
            : scope.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toSet(),
        expiresAt: _now().toUtc().add(Duration(seconds: lifetime)),
      );
    } on Object {
      throw const ChatGptException('ChatGPT devolvió una sesión inválida.');
    }
  }

  Future<JsonWebTokenClaims> _verifyIdentity(
    _Tokens tokens,
    String clientId, {
    String? nonce,
    String? subject,
  }) async {
    final encoded = tokens.idToken;
    if (encoded == null || encoded.split('.').length != 3) {
      throw const ChatGptException('ChatGPT no devolvió una identidad válida.');
    }
    try {
      final cached =
          _keys != null &&
          _now().difference(_keysFetchedAt!) < const Duration(minutes: 10);
      final keys = cached ? _keys! : await _fetchKeys();
      Future<JsonWebTokenClaims> verify(JsonWebKeyStore store) async =>
          (await JsonWebToken.decodeAndVerify(
            encoded,
            store,
            allowedArguments: const ['RS256'],
          )).claims;
      JsonWebTokenClaims claims;
      try {
        claims = await verify(keys);
      } on JoseException {
        if (!cached) rethrow;
        claims = await verify(await _fetchKeys());
      }
      final now = _now().toUtc();
      const skew = Duration(seconds: 5);
      final audience = claims.audience;
      final expires = claims.expiry,
          issuedAt = claims.issuedAt,
          notBefore = claims.notBefore;
      final authorizedParty = claims['azp'];
      final accessHash = claims['at_hash'];
      if (claims.issuer.toString() != _issuer ||
          audience == null ||
          !audience.contains(clientId) ||
          ((audience.length > 1 || authorizedParty != null) &&
              authorizedParty != clientId) ||
          expires == null ||
          !expires.isAfter(now.subtract(skew)) ||
          issuedAt == null ||
          issuedAt.isAfter(now.add(skew)) ||
          (notBefore != null && notBefore.isAfter(now.add(skew))) ||
          (nonce != null && claims['nonce'] != nonce) ||
          claims.subject == null ||
          claims.subject!.isEmpty ||
          (subject != null && claims.subject != subject) ||
          (accessHash != null &&
              accessHash !=
                  _base64Url(
                    sha256
                        .convert(utf8.encode(tokens.accessToken))
                        .bytes
                        .take(16)
                        .toList(),
                  ))) {
        throw const FormatException('ID token claims');
      }
      return claims;
    } on ChatGptException {
      rethrow;
    } on Object {
      throw const ChatGptException(
        'No se pudo verificar la identidad de la cuenta de ChatGPT.',
      );
    }
  }

  Future<JsonWebKeyStore> _fetchKeys() async {
    final json = await _jsonGet(Uri.parse('$_issuer/.well-known/jwks.json'));
    final keys = JsonWebKeyStore()..addKeySet(JsonWebKeySet.fromJson(json));
    _keys = keys;
    _keysFetchedAt = _now();
    return keys;
  }

  Future<Map<String, dynamic>> _jsonGet(Uri url) async {
    final response = await _send('GET', url);
    if (response.statusCode != 200) throw _httpError(response);
    return _jsonObject(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String>? form,
  }) async {
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      method,
      url,
      abortTrigger: abort.future,
    )..followRedirects = false;
    if (form != null) request.bodyFields = form;
    try {
      final response = await _http.send(request).timeout(_networkTimeout);
      return await http.Response.fromStream(response).timeout(_networkTimeout);
    } on TimeoutException {
      throw const ChatGptException('ChatGPT tardó demasiado en responder.');
    } on http.ClientException {
      throw const ChatGptException(
        'No se pudo conectar con ChatGPT. Revisá tu conexión.',
      );
    } finally {
      abort.complete();
    }
  }
}

class _BrowserGrant {
  const _BrowserGrant({this.code, this.clientId, this.error});

  final String? code, clientId;
  final ChatGptException? error;

  static _BrowserGrant read(Map<String, List<String>> params, String? savedId) {
    if (params.containsKey('error')) {
      final denied = params['error']?.singleOrNull == 'access_denied';
      return _BrowserGrant(
        error: ChatGptException(
          denied
              ? 'Cancelaste la autorización de ChatGPT.'
              : 'ChatGPT no pudo autorizar la conexión. Volvé a intentarlo.',
          code: denied ? 'access_denied' : 'authorization_error',
        ),
      );
    }
    final code = params['code']?.singleOrNull;
    final clientValues = params['client_id'];
    final issued = clientValues?.singleOrNull;
    final clientId = savedId ?? issued;
    if (code == null ||
        code.isEmpty ||
        clientId == null ||
        clientId.isEmpty ||
        clientId == _ChatGptOAuth._dynamicId ||
        (clientValues != null && issued != clientId)) {
      return const _BrowserGrant(
        error: ChatGptException(
          'ChatGPT no devolvió un registro de cuenta válido.',
          code: 'invalid_callback',
        ),
      );
    }
    return _BrowserGrant(code: code, clientId: clientId);
  }
}

String _browserReturnPage(_BrowserGrant? grant) {
  final title = switch (grant) {
    null => 'Solicitud inválida',
    _BrowserGrant(error: null) => 'Autorización recibida',
    _BrowserGrant(error: ChatGptException(code: 'access_denied')) =>
      'Solicitud cancelada',
    _ => 'Autorización incompleta',
  };
  final returnLink = Platform.isAndroid && grant != null
      ? '<a href="intent://open#Intent;scheme=nala-chatgpt-return;package=com.felipe.apuntes;end">Volver a Nala</a>'
      : '';
  return '''<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$title · Nala</title>
<style>
html{color-scheme:light dark}body{font:1rem/1.5 system-ui;margin:0;padding:2rem}
main{max-width:28rem;margin:12vh auto}h1{line-height:1.2}a{display:inline-block;padding:.75rem 1rem;border:1px solid currentColor;border-radius:.5rem;color:inherit}
</style><script>history.replaceState(null,"",location.pathname)</script></head>
<body><main><h1>$title</h1><p>Volvé a Nala para ver el estado de la conexión.</p>$returnLink</main></body></html>''';
}

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

String _randomUrlString() {
  final random = Random.secure();
  return _base64Url(List.generate(32, (_) => random.nextInt(256)));
}

class _AccountRecord {
  const _AccountRecord({
    required this.id,
    required this.subject,
    required this.email,
    this.tokens,
  });

  final String id, subject, email;
  final _Tokens? tokens;

  ChatGptAccount get publicInfo => ChatGptAccount(
    id: id,
    email: email,
    connected: tokens?.scopes.contains(_directScope) ?? false,
  );

  _AccountRecord withoutCredentials() =>
      _AccountRecord(id: id, subject: subject, email: email);

  Map<String, Object?> toJson() => {
    'id': id,
    'subject': subject,
    'email': email,
    'tokens': ?tokens?.toJson(),
  };

  factory _AccountRecord.fromJson(Map<String, dynamic> json) => _AccountRecord(
    id: json['id'] as String,
    subject: json['subject'] as String,
    email: json['email'] as String,
    tokens: json['tokens'] == null
        ? null
        : _Tokens.fromJson(_jsonObject(json['tokens'])),
  );
}

class _Tokens {
  const _Tokens({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    required this.scopes,
    required this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken, idToken;
  final Set<String> scopes;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': ?refreshToken,
    'idToken': ?idToken,
    'scopes': scopes.toList(),
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory _Tokens.fromJson(Map<String, dynamic> json) => _Tokens(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String?,
    idToken: json['idToken'] as String?,
    scopes: (json['scopes'] as List).cast<String>().toSet(),
    expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
  );
}
