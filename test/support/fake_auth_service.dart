import 'package:apuntes/account/auth_service.dart';

class FakeAuthService implements AuthService {
  FakeAuthService({
    this.current = const GoogleAccount('student', 'student@example.invalid'),
  });
  @override
  GoogleAccount? current;
  int refreshes = 0;
  @override
  bool get secureStorageAvailable => true;
  @override
  Future<GoogleAccount?> restore() async => current;
  @override
  Future<GoogleAccount> signIn() async => current!;
  @override
  Future<Map<String, String>> authorizationHeaders({
    bool forceRefresh = false,
  }) async {
    if (current == null) throw const AuthRequired();
    if (forceRefresh) refreshes++;
    return {'Authorization': 'Bearer fixture-token'};
  }

  @override
  Future<void> signOut() async {
    current = null;
  }

  @override
  Future<void> cancelSignIn() async {}
  @override
  void dispose() {}
}

class FakeTokenStore implements TokenStore {
  String? value;
  bool unavailable = false;
  @override
  Future<String?> read() async {
    if (unavailable) throw StateError('Sin llavero');
    return value;
  }

  @override
  Future<void> write(String value) async {
    if (unavailable) throw StateError('Sin llavero');
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}
