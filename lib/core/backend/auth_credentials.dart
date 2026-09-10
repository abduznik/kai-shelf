import 'models.dart';

/// One constructor per backend's auth shape — the actual auth mechanism
/// can't be unified across Suwayomi/Komga/Kavita, only its detection can.
sealed class AuthCredentials {
  const AuthCredentials();

  const factory AuthCredentials.suwayomi({String? password}) =
      SuwayomiCredentials;

  const factory AuthCredentials.komgaPassword(
      {required String email,
      required String password}) = KomgaPasswordCredentials;

  const factory AuthCredentials.komgaApiKey({required String apiKey}) =
      KomgaApiKeyCredentials;

  const factory AuthCredentials.kavita({required String apiKey}) =
      KavitaCredentials;
}

class SuwayomiCredentials extends AuthCredentials {
  const SuwayomiCredentials({this.password});
  final String? password;
}

class KomgaPasswordCredentials extends AuthCredentials {
  const KomgaPasswordCredentials({required this.email, required this.password});
  final String email;
  final String password;
}

class KomgaApiKeyCredentials extends AuthCredentials {
  const KomgaApiKeyCredentials({required this.apiKey});
  final String apiKey;
}

class KavitaCredentials extends AuthCredentials {
  const KavitaCredentials({required this.apiKey});
  final String apiKey;
}

class AuthResult {
  const AuthResult.success(this.connectionInfo)
      : success = true,
        error = null;
  const AuthResult.failure(this.error)
      : success = false,
        connectionInfo = null;

  final bool success;
  final String? error;
  final ServerConnectionInfo? connectionInfo;
}

/// Thrown by adapters when a session/token is rejected mid-use so the app
/// can force re-login rather than surfacing a generic network error.
class BackendAuthException implements Exception {
  const BackendAuthException(
      [this.message = 'Session expired or unauthorized']);
  final String message;

  @override
  String toString() => 'BackendAuthException: $message';
}
