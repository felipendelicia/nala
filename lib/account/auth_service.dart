const driveScope = 'https://www.googleapis.com/auth/drive.file';

class GoogleAccount {
  const GoogleAccount(this.id, this.email);
  final String id, email;
  Map<String, String> toJson() => {'id': id, 'email': email};
  factory GoogleAccount.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String, email = json['email'] as String;
    if (id.isEmpty || email.isEmpty) {
      throw const FormatException('Cuenta inválida');
    }
    return GoogleAccount(id, email);
  }
}

class AuthRequired implements Exception {
  const AuthRequired();
}

class AuthCancelled implements Exception {
  const AuthCancelled();
}

abstract interface class AuthService {
  GoogleAccount? get current;
  bool get secureStorageAvailable;
  Future<GoogleAccount?> restore();
  Future<GoogleAccount> signIn();
  Future<Map<String, String>> authorizationHeaders({bool forceRefresh = false});
  Future<void> signOut();
  Future<void> cancelSignIn();
  void dispose();
}

abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}
