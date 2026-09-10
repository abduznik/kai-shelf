import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/detector/backend_detector.dart';
import '../backend/komga/komga_backend.dart';
import '../backend/kavita/kavita_backend.dart';
import '../backend/models.dart';
import '../backend/server_backend.dart';
import '../backend/suwayomi/suwayomi_backend.dart';
import '../storage/secure_credentials.dart';

/// Current active server connection, or null if no server is configured yet.
/// This is the single source of truth for "which server + session is active."
final activeConnectionProvider =
    StateProvider<ServerConnectionInfo?>((ref) => null);

/// Derives the concrete backend adapter from the active connection.
///
/// This switch is the ONLY place outside lib/core/backend/ allowed to
/// reference a concrete adapter class (SuwayomiBackend/KomgaBackend/
/// KavitaBackend) — every feature module reads through this provider and
/// the shared DTOs only.
final activeBackendProvider = Provider<ServerBackend?>((ref) {
  final connection = ref.watch(activeConnectionProvider);
  if (connection == null) return null;

  switch (connection.type) {
    case BackendType.suwayomi:
      return SuwayomiBackend(connection);
    case BackendType.komga:
      return KomgaBackend(connection);
    case BackendType.kavita:
      return KavitaBackend(connection);
  }
});

final backendDetectorProvider = Provider<BackendDetector>((ref) {
  final detector = BackendDetector();
  ref.onDispose(detector.dispose);
  return detector;
});

final secureCredentialsProvider = Provider<SecureCredentialsStore>((ref) {
  return SecureCredentialsStore();
});
