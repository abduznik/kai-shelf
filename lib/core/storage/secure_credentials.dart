import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the sensitive half of a server connection (password/API
/// key/session token) — never held in plaintext shared_preferences.
class SecureCredentialsStore {
  SecureCredentialsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String serverId, String field) => 'server.$serverId.$field';

  Future<void> writeSecret(String serverId, String field, String value) {
    return _storage.write(key: _key(serverId, field), value: value);
  }

  Future<String?> readSecret(String serverId, String field) {
    return _storage.read(key: _key(serverId, field));
  }

  Future<void> deleteAll(String serverId) async {
    for (final field in ['password', 'apiKey', 'sessionToken']) {
      await _storage.delete(key: _key(serverId, field));
    }
  }
}
