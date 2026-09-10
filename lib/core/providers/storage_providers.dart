import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/app_database.dart';
import '../storage/reading_progress_repository.dart';

/// Null on web: sqflite has no web-native storage backend, and this app
/// doesn't ship the sqflite_common_ffi_web/IndexedDB bridge — reading
/// progress and downloads simply aren't persisted across sessions there.
final appDatabaseProvider = FutureProvider<AppDatabase?>((ref) async {
  if (kIsWeb) return null;
  return AppDatabase.open();
});

final readingProgressRepositoryProvider =
    Provider<ReadingProgressRepository?>((ref) {
  final dbAsync = ref.watch(appDatabaseProvider);
  final db = dbAsync.value;
  if (db == null) return null;
  return ReadingProgressRepository(db);
});
