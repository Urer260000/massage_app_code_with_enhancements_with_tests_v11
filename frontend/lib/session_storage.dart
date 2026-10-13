import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the refresh token between app launches so guests stay signed in.
abstract class SessionStorage {
  Future<String?> read();
  Future<void> write(String refreshToken);
  Future<void> clear();
}

/// Keychain on iOS, encrypted storage on Android, browser storage on web.
class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'refresh_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      // Unreadable storage (e.g. after a device restore) just means signing in again.
      return null;
    }
  }

  @override
  Future<void> write(String refreshToken) async {
    try {
      await _storage.write(key: _key, value: refreshToken);
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

/// For tests, and anywhere sessions shouldn't outlive the app.
class MemorySessionStorage implements SessionStorage {
  MemorySessionStorage([this.value]);
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String refreshToken) async => value = refreshToken;

  @override
  Future<void> clear() async => value = null;
}
