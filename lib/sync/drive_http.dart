import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../account/auth_service.dart';
import 'remote_store.dart';

class DriveHttp {
  DriveHttp({
    required this.auth,
    required this.client,
    required this.accountId,
  });
  final AuthService auth;
  final http.Client client;
  final String accountId;
  bool _closed = false;
  Future<http.Response> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Uint8List? bytes,
    String? body,
    Set<int> accepted = const {200, 201, 204},
  }) async {
    // Never forward account credentials to an arbitrary upload-session URL.
    if (uri.scheme != 'https' ||
        !{'www.googleapis.com', 'content.googleapis.com'}.contains(uri.host)) {
      throw const FormatException('Destino de Drive inválido');
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      if (_closed || auth.current?.id != accountId) {
        throw const RemoteSignInRequired();
      }
      Map<String, String> authorization;
      try {
        authorization = await auth.authorizationHeaders(
          forceRefresh: attempt == 1,
        );
      } on AuthRequired {
        throw const RemoteSignInRequired();
      }
      if (_closed || auth.current?.id != accountId) {
        throw const RemoteSignInRequired();
      }
      final request = http.Request(method, uri)
        ..headers.addAll({...authorization, ...headers});
      if (bytes != null) request.bodyBytes = bytes;
      if (body != null) request.body = body;
      final response = await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(const Duration(seconds: 30));
      if (_closed || auth.current?.id != accountId) {
        throw const RemoteSignInRequired();
      }
      if (response.statusCode == 401) {
        if (attempt == 0) continue;
        throw const RemoteSignInRequired();
      }
      if (response.statusCode == 403) throw const RemoteSignInRequired();
      if (response.statusCode == 429 || response.statusCode >= 500) {
        final value = response.headers['retry-after'];
        Duration delay = Duration(milliseconds: 2000 + Random().nextInt(1000));
        if (value != null) {
          final seconds = int.tryParse(value);
          if (seconds != null) {
            delay = Duration(seconds: max(0, seconds));
          } else {
            try {
              final until = HttpDate.parse(
                value,
              ).difference(DateTime.now().toUtc());
              delay = until.isNegative ? Duration.zero : until;
            } on FormatException {
              /* Use jittered retry. */
            }
          }
        }
        throw RemoteRetryLater(delay);
      }
      if (!accepted.contains(response.statusCode)) {
        throw HttpException(
          'Drive no pudo completar la operación (${response.statusCode}).',
        );
      }
      return response;
    }
    throw const RemoteSignInRequired();
  }

  void close() {
    _closed = true;
    client.close();
  }
}
