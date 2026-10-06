import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../backend/auth_credentials.dart';
import '../backend/kavita/kavita_backend.dart';
import '../backend/komga/komga_backend.dart';
import '../backend/models.dart';
import '../backend/server_backend.dart';
import '../backend/suwayomi/suwayomi_backend.dart';

/// Remembers the active server connection across app restarts.
///
/// The whole connection (URL, auth headers, API key, tokens) goes into
/// secure storage as one blob, since the auth headers and tokens are
/// credentials and must not sit in plain shared_preferences.
class SessionStore {
  SessionStore(
      {FlutterSecureStorage? storage,
      ServerBackend Function(ServerConnectionInfo)? backendFactory})
      : _storage = storage ?? const FlutterSecureStorage(),
        _backendFactory = backendFactory ?? _defaultBackend;

  static ServerBackend _defaultBackend(ServerConnectionInfo info) =>
      switch (info.type) {
        BackendType.suwayomi => SuwayomiBackend(info),
        BackendType.komga => KomgaBackend(info),
        BackendType.kavita => KavitaBackend(info),
      };

  final ServerBackend Function(ServerConnectionInfo) _backendFactory;

  static const _key = 'session.activeConnection';

  final FlutterSecureStorage _storage;

  Future<void> save(ServerConnectionInfo connection) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(connection.toJson()));
    } catch (_) {
      // Storage unavailable (e.g. locked keychain): the session simply
      // won't survive a restart; don't break the login that just worked.
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }

  Future<ServerConnectionInfo?> load() async {
    try {
      // Bounded so a stuck keychain can't leave the app on its splash screen.
      final raw =
          await _storage.read(key: _key).timeout(const Duration(seconds: 5));
      if (raw == null) return null;
      return ServerConnectionInfo.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Unreadable or from an incompatible version: treat as signed out.
      return null;
    }
  }

  /// Loads the saved connection and checks it still works.
  ///
  /// A rejected session is refreshed where the server allows it (Kavita's
  /// short-lived token is re-minted from the stored API key) and otherwise
  /// discarded. A network failure keeps the session: being offline or the
  /// server being down is not a reason to sign the user out.
  Future<ServerConnectionInfo?> restore() async {
    final saved = await load();
    if (saved == null) return null;

    final backend = _backendFactory(saved);

    try {
      // Bounded too: an unreachable server shouldn't hold up startup. A
      // timeout lands in the catch-all below and keeps the session.
      await backend.getLibraries().timeout(const Duration(seconds: 8));
      return saved;
    } on BackendAuthException {
      if (saved.type == BackendType.kavita && (saved.apiKey ?? '').isNotEmpty) {
        try {
          final result =
              await backend.login(KavitaCredentials(apiKey: saved.apiKey!));
          if (result.success && result.connectionInfo != null) {
            await save(result.connectionInfo!);
            return result.connectionInfo;
          }
        } catch (_) {
          return saved;
        }
      }
      await clear();
      return null;
    } catch (_) {
      return saved;
    }
  }
}
