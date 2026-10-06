import 'dart:io';
import 'auth_service.dart';
import 'android_auth_service.dart';
import 'linux_auth_service.dart';

class AuthConfig {
  const AuthConfig({
    this.webClientId = const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    this.desktopClientId = const String.fromEnvironment(
      'GOOGLE_DESKTOP_CLIENT_ID',
    ),
    this.desktopClientSecret = const String.fromEnvironment(
      'GOOGLE_DESKTOP_CLIENT_SECRET',
    ),
  });
  final String webClientId, desktopClientId, desktopClientSecret;
  bool get configured => (Platform.isAndroid ? webClientId : desktopClientId)
      .endsWith('.apps.googleusercontent.com');
  AuthService? create() => !configured
      ? null
      : Platform.isAndroid
      ? AndroidAuthService(webClientId)
      : LinuxAuthService(
          clientId: desktopClientId,
          clientSecret: desktopClientSecret,
        );
}
