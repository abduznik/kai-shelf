import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/models.dart';
import '../backend/server_backend.dart';
import 'backend_providers.dart';
import 'library_providers.dart';

/// The active backend's named categories, or empty when it has none.
final categoriesProvider =
    FutureProvider.autoDispose<List<KsCategory>>((ref) async {
  final backend = ref.watch(activeBackendProvider);
  if (backend is! CategoryCapableBackend) return [];
  return (backend as CategoryCapableBackend).getCategories();
});

final categoryMangaProvider =
    FutureProvider.autoDispose.family<List<KsManga>, String>((ref, id) async {
  final backend = ref.watch(activeBackendProvider);
  if (backend is! CategoryCapableBackend) return [];
  return (backend as CategoryCapableBackend).getCategoryManga(id);
});

/// Refreshes everything that shows category names, counts or membership.
void invalidateCategoryData(WidgetRef ref) {
  ref.invalidate(categoriesProvider);
  ref.invalidate(categoryMangaProvider);
  ref.invalidate(libraryListProvider);
  ref.invalidate(mangaListProvider);
}

/// Per-manga switch for the detail screen's "bookmarked chapters only"
/// filter, so it resets when the screen is left.
final bookmarkedOnlyProvider =
    StateProvider.autoDispose.family<bool, String>((ref, mangaId) => false);
