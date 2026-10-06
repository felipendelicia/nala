import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'auth_service.dart';

class AndroidAuthService implements AuthService {
  AndroidAuthService(this.webClientId);
  final String webClientId;
  final _sdk = GoogleSignIn.instance;
  Future<void>? _initialization;
  GoogleSignInAccount? _account;
  Completer<void>? _cancel;
  String? _lastToken;
  bool _closed = false;
  int _generation = 0;
  Future<void> _initialize() =>
      _initialization ??= _sdk.initialize(serverClientId: webClientId);
  @override
  GoogleAccount? get current =>
      _account == null ? null : GoogleAccount(_account!.id, _account!.email);
  @override
  bool get secureStorageAvailable => true;
  @override
  Future<GoogleAccount?> restore() async {
    await _initialize();
    final generation = _generation;
    try {
      final restored = await _sdk.attemptLightweightAuthentication();
      if (!_closed && generation == _generation) _account = restored;
      return current;
    } on GoogleSignInException {
      return null;
    }
  }

  Future<T> _wait<T>(Future<T> future, Completer<void> cancelled) => Future.any(
    [future, cancelled.future.then<T>((_) => throw const AuthCancelled())],
  );
  @override
  Future<GoogleAccount> signIn() async {
    if (_closed || _cancel != null) throw const AuthCancelled();
    final cancelled = _cancel = Completer<void>();
    final generation = _generation;
    try {
      await _wait(_initialize(), cancelled);
      // Explicit connection also allows selecting another Google account.
      await _wait(_sdk.signOut(), cancelled);
      final account = await _wait(
        _sdk.authenticate(scopeHint: [driveScope]),
        cancelled,
      );
      await _wait(
        account.authorizationClient.authorizeScopes([driveScope]),
        cancelled,
      );
      if (_closed || generation != _generation) throw const AuthCancelled();
      _account = account;
      _lastToken = null;
      return current!;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthCancelled();
      }
      throw const AuthRequired();
    } finally {
      if (identical(_cancel, cancelled)) _cancel = null;
    }
  }

  @override
  Future<Map<String, String>> authorizationHeaders({
    bool forceRefresh = false,
  }) async {
    final account = _account, generation = _generation;
    if (_closed || account == null) throw const AuthRequired();
    if (forceRefresh && _lastToken != null) {
      await account.authorizationClient.clearAuthorizationToken(
        accessToken: _lastToken!,
      );
    }
    final headers = await account.authorizationClient.authorizationHeaders([
      driveScope,
    ]);
    if (headers == null ||
        _closed ||
        generation != _generation ||
        !identical(_account, account)) {
      throw const AuthRequired();
    }
    final authorization = headers['Authorization'];
    _lastToken = authorization?.startsWith('Bearer ') == true
        ? authorization!.substring(7)
        : null;
    return headers;
  }

  @override
  Future<void> cancelSignIn() async {
    _generation++;
    if (_cancel != null && !_cancel!.isCompleted) _cancel!.complete();
  }

  @override
  Future<void> signOut() async {
    await cancelSignIn();
    _account = null;
    _lastToken = null;
    if (_initialization != null) await _sdk.signOut();
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(cancelSignIn());
  }
}
