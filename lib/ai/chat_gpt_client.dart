import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:uuid/uuid.dart';

import '../account/token_store.dart';

part 'chat_gpt_oauth.dart';

const _resource = 'https://api.openai.com/v1';
const _issuer = 'https://auth.openai.com';
const _directScope = 'chatgpt.tokens.use.direct';
const _scopes =
    'openid profile email offline_access resource.invoke $_directScope';
const _storageKey = 'nala-chatgpt-v1';
const _networkTimeout = Duration(seconds: 25);

class ChatGptException implements Exception {
  const ChatGptException(
    this.message, {
    this.statusCode,
    this.code,
    this.requestId,
  });

  final String message;
  final int? statusCode;
  final String? code, requestId;

  @override
  String toString() => message;
}

class ChatGptAccount {
  const ChatGptAccount({
    required this.id,
    required this.email,
    required this.connected,
  });

  final String id, email;
  final bool connected;
}

class ChatGptModel {
  const ChatGptModel({required this.slug, required this.displayName});

  final String slug, displayName;
}

/// Local credentials for the official Sign in with ChatGPT public-client flow.
class ChatGptClient extends ChangeNotifier {
  ChatGptClient({
    TokenStore? tokenStore,
    this.httpClient,
    DateTime Function()? now,
  }) : _store = tokenStore ?? const SecureTokenStore(),
       _now = now ?? DateTime.now;

  final TokenStore _store;
  final http.Client? httpClient;
  http.Client? _ownedHttp;
  http.Client get _http => httpClient ?? (_ownedHttp ??= http.Client());
  final DateTime Function() _now;
  late final _oauth = _ChatGptOAuth(_http, _now);
  final Map<String, _AccountRecord> _records = {};
  final Set<Completer<void>> _requests = {};
  String? _hostId, _activeId;
  bool _loaded = false, _closed = false;
  Future<void> _accountOperations = Future.value();

  List<ChatGptAccount> get accounts =>
      List.unmodifiable(_records.values.map((r) => r.publicInfo));
  ChatGptAccount? get activeAccount => _records[_activeId]?.publicInfo;
  bool get connected => activeAccount?.connected ?? false;

  void cancelSignIn() => _oauth.cancel();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final operation = _accountOperations.then((_) async {
      if (_closed) {
        throw const ChatGptException('Se cerró la conexión con ChatGPT.');
      }
      return action();
    });
    _accountOperations = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> load() => _serialize(_load);

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final value = await _store.read(_storageKey);
      if (value != null) {
        final saved = _jsonObject(jsonDecode(value));
        final records = (saved['accounts'] as List).map(
          (json) => _AccountRecord.fromJson(_jsonObject(json)),
        );
        final hostId = saved['hostId'] as String;
        final activeId = saved['activeId'] as String?;
        _records.addEntries(
          records.map((record) => MapEntry(record.id, record)),
        );
        _hostId = hostId;
        _activeId = activeId;
      }
      _loaded = true;
      _notify();
    } catch (_) {
      throw const ChatGptException(
        'No se pudo leer el llavero de este dispositivo.',
      );
    }
  }

  Future<void> _save() async {
    try {
      await _store.write(
        _storageKey,
        jsonEncode({
          'hostId': _hostId,
          'activeId': _activeId,
          'accounts': _records.values.map((r) => r.toJson()).toList(),
        }),
      );
    } catch (_) {
      throw const ChatGptException(
        'No se pudieron guardar los cambios en el llavero de este dispositivo.',
      );
    } finally {
      _notify();
    }
  }

  Future<void> signIn(
    Future<bool> Function(Uri) openBrowser, {
    String? accountId,
    FutureOr<void> Function()? onBrowserReturn,
  }) => _serialize(() async {
    await _load();
    final existing = _records[accountId];
    if (accountId != null && existing == null) {
      throw const ChatGptException(
        'La cuenta seleccionada ya no está disponible.',
      );
    }
    // Persist the installation identifier before it is sent to the issuer.
    if (_hostId == null) {
      _hostId = 'urn:uuid:${const Uuid().v4()}';
      try {
        await _save();
      } catch (_) {
        _hostId = null;
        rethrow;
      }
    }
    final record = await _oauth.signIn(
      openBrowser,
      hostId: _hostId!,
      existing: existing,
      onBrowserReturn: onBrowserReturn,
    );
    if (_closed) return;
    final matching = _records[record.id];
    if (matching != null && matching.subject != record.subject) {
      throw const ChatGptException(
        'ChatGPT devolvió una identidad distinta para esta cuenta.',
      );
    }
    _abortRequests();
    _records[record.id] = record;
    _activeId = record.id;
    await _save();
  });

  Future<void> useAccount(String accountId) => _serialize(() async {
    await _load();
    if (_records[accountId]?.publicInfo.connected != true) {
      throw const ChatGptException(
        'Volvé a iniciar sesión para usar esta cuenta.',
      );
    }
    _abortRequests();
    _activeId = accountId;
    await _save();
  });

  /// Returns whether revocation was confirmed. Local sign-out still proceeds.
  Future<bool> signOut() => _serialize(() async {
    await _load();
    final record = _records[_activeId];
    if (record == null) return true;
    _abortRequests();
    final revoked = await _oauth.revoke(record);
    _records[record.id] = record.withoutCredentials();
    _activeId = null;
    await _save();
    return revoked;
  });

  Future<String> _accessToken() async {
    await _load();
    final selected = _records[_activeId];
    if (selected == null || selected.tokens == null) {
      throw const ChatGptException('Iniciá sesión con ChatGPT para continuar.');
    }
    var active = selected;
    if (!active.tokens!.scopes.contains(_directScope)) {
      throw const ChatGptException(
        'Autorizá a Nala a usar tu plan de ChatGPT.',
      );
    }
    if (!_now()
        .add(const Duration(minutes: 1))
        .isBefore(active.tokens!.expiresAt)) {
      try {
        active = await _oauth.refresh(active);
      } on ChatGptException catch (error) {
        if (const {
          'invalid_grant',
          'invalid_refresh_token',
          'token_expired',
          'refresh_token_expired',
          'refresh_token_invalidated',
          'refresh_token_reused',
        }.contains(error.code)) {
          _abortRequests();
          _records[active.id] = active.withoutCredentials();
          await _save();
          throw const ChatGptException(
            'La sesión de ChatGPT venció. Volvé a iniciar sesión.',
          );
        }
        rethrow;
      }
      _records[active.id] = active;
      await _save();
      if (!active.tokens!.scopes.contains(_directScope)) {
        throw const ChatGptException(
          'Autorizá a Nala a usar tu plan de ChatGPT.',
        );
      }
    }
    return active.tokens!.accessToken;
  }

  Future<T> _authorized<T>(
    String method,
    String path, {
    Map<String, Object>? payload,
    String? expectedAccountId,
    required Future<T> Function(http.StreamedResponse) consume,
  }) async {
    final abort = Completer<void>();
    final token = await _serialize(() async {
      if (expectedAccountId != null && _activeId != expectedAccountId) {
        throw const ChatGptException(
          'Cambió la cuenta de ChatGPT. Volvé a enviar la solicitud.',
        );
      }
      final token = await _accessToken();
      if (_closed) {
        throw const ChatGptException('Se cerró la conexión con ChatGPT.');
      }
      _requests.add(abort);
      return token;
    });
    try {
      final request =
          http.AbortableRequest(
              method,
              Uri.parse('$_resource/$path'),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..headers['authorization'] = 'Bearer $token';
      if (payload != null) {
        request.headers['content-type'] = 'application/json';
        request.headers['accept'] = 'text/event-stream';
        request.body = jsonEncode(payload);
      }
      final response = await _http.send(request).timeout(_networkTimeout);
      if (response.statusCode != 200) {
        throw _httpError(
          await http.Response.fromStream(response).timeout(_networkTimeout),
        );
      }
      return await consume(response);
    } on TimeoutException {
      throw const ChatGptException('ChatGPT tardó demasiado en responder.');
    } on http.RequestAbortedException {
      throw const ChatGptException('Se canceló la solicitud a ChatGPT.');
    } on http.ClientException {
      throw const ChatGptException(
        'No se pudo conectar con ChatGPT. Revisá tu conexión.',
      );
    } on FormatException {
      throw const ChatGptException(
        'ChatGPT devolvió una respuesta que Nala no pudo leer.',
      );
    } finally {
      _requests.remove(abort);
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<List<ChatGptModel>> listModels() => _authorized(
    'GET',
    'models',
    consume: (response) async {
      final body = await http.Response.fromStream(
        response,
      ).timeout(_networkTimeout);
      final catalog = _jsonObject(
        jsonDecode(utf8.decode(body.bodyBytes)),
      )['models'];
      if (catalog is! List) throw const FormatException('Model catalog');
      return List.unmodifiable([
        for (final model in catalog.whereType<Map<String, dynamic>>())
          if (model['visibility'] == 'list' &&
              model['slug'] is String &&
              model['display_name'] is String)
            ChatGptModel(
              slug: model['slug'] as String,
              displayName: model['display_name'] as String,
            ),
      ]);
    },
  );

  Future<String> respond({
    required String model,
    required String instructions,
    required String text,
    List<({bool isUser, String text})> history = const [],
    Uint8List? notebookPdf,
    String? expectedAccountId,
    void Function(String)? onDelta,
  }) => _authorized(
    'POST',
    'responses',
    expectedAccountId: expectedAccountId,
    payload: {
      'model': model,
      'instructions': instructions,
      'input': [
        for (final turn in history)
          {'role': turn.isUser ? 'user' : 'assistant', 'content': turn.text},
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': text},
            if (notebookPdf != null)
              {
                'type': 'input_file',
                'filename': 'cuaderno.pdf',
                'file_data':
                    'data:application/pdf;base64,${base64Encode(notebookPdf)}',
              },
          ],
        },
      ],
      'store': false,
      'stream': true,
    },
    consume: (response) async {
      final output = StringBuffer();
      await for (final event in _responseEvents(response.stream)) {
        switch (event['type']) {
          case 'response.output_text.delta':
            final delta = event['delta'];
            if (delta is! String) throw const FormatException('Text delta');
            output.write(delta);
            onDelta?.call(delta);
          case 'response.completed':
            final result = output.toString().trim();
            if (result.isEmpty) {
              throw const ChatGptException('ChatGPT no devolvió texto.');
            }
            return result;
          case 'response.failed':
            final details = event['response'];
            final error = details is Map ? details['error'] : null;
            throw _providerError(
              code: error is Map ? error['code'] as String? : null,
              requestId: response.headers['x-request-id'],
            );
          case 'error':
            throw _providerError(
              code: event['code'] as String?,
              requestId: response.headers['x-request-id'],
            );
          case 'response.incomplete':
            throw const ChatGptException(
              'ChatGPT devolvió un resultado incompleto.',
            );
        }
      }
      throw const ChatGptException(
        'La respuesta de ChatGPT se interrumpió antes de terminar.',
      );
    },
  );

  void _abortRequests() {
    for (final abort in _requests) {
      if (!abort.isCompleted) abort.complete();
    }
    _requests.clear();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _abortRequests();
    final client = _ownedHttp ?? httpClient;
    if (client != null) {
      _oauth.cancel();
      client.close();
    }
    super.dispose();
  }
}

Map<String, dynamic> _jsonObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected JSON object');
  }
  return value;
}

Stream<Map<String, dynamic>> _responseEvents(Stream<List<int>> source) async* {
  final data = <String>[];
  await for (final line
      in source
          .timeout(const Duration(minutes: 2))
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    if (line.startsWith('data:')) {
      data.add(line.substring(5).trimLeft());
    } else if (line.isEmpty && data.isNotEmpty) {
      final message = data.join('\n');
      data.clear();
      if (message != '[DONE]') yield _jsonObject(jsonDecode(message));
    }
  }
}

ChatGptException _httpError(http.Response response) {
  String? code;
  try {
    final payload = _jsonObject(jsonDecode(utf8.decode(response.bodyBytes)));
    final error = payload['error'];
    if (error is String) code = error;
    if (error is Map && error['code'] is String) code = error['code'] as String;
  } on FormatException {
    // Admission failures need not contain a structured error body.
  }
  return _providerError(
    code: code,
    statusCode: response.statusCode,
    requestId: response.headers['x-request-id'],
  );
}

ChatGptException _providerError({
  String? code,
  int? statusCode,
  String? requestId,
}) {
  final message = switch (code) {
    'subscription_sharing_user_not_eligible' =>
      'Esta cuenta o espacio de trabajo no puede usar el plan con Nala.',
    'subscription_sharing_usage_limit_exceeded' ||
    'subscription_sharing_usage_unavailable' =>
      'Alcanzaste el límite de uso de ChatGPT para esta solicitud. Revisá el uso de tu plan.',
    'subscription_sharing_unsupported_capability' =>
      'El modelo seleccionado no admite este contenido. Probá otro modelo.',
    _ => switch (statusCode) {
      401 =>
        'ChatGPT no aceptó esta sesión. Revisá los permisos o volvé a iniciar sesión.',
      403 => 'ChatGPT no habilitó esta operación para tu cuenta o región.',
      429 => 'ChatGPT alcanzó un límite de uso. Revisá el uso de tu plan.',
      503 => 'El servicio de ChatGPT no está disponible por el momento.',
      _ => 'ChatGPT no pudo completar la solicitud.',
    },
  };
  return ChatGptException(
    message,
    code: code,
    statusCode: statusCode,
    requestId: requestId,
  );
}
