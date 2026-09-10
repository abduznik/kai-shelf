import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/models.dart';
import 'backend_providers.dart';

final libraryListProvider =
    FutureProvider.autoDispose<List<KsLibrary>>((ref) async {
  final backend = ref.watch(activeBackendProvider);
  if (backend == null) return [];
  return backend.getLibraries();
});

class MangaListParams {
  const MangaListParams({this.libraryId, this.searchQuery});

  final String? libraryId;
  final String? searchQuery;

  @override
  bool operator ==(Object other) =>
      other is MangaListParams &&
      other.libraryId == libraryId &&
      other.searchQuery == searchQuery;

  @override
  int get hashCode => Object.hash(libraryId, searchQuery);
}

final mangaListProvider =
    FutureProvider.autoDispose.family<List<KsManga>, MangaListParams>((
  ref,
  params,
) async {
  final backend = ref.watch(activeBackendProvider);
  if (backend == null) return [];
  return backend.getMangaList(
      libraryId: params.libraryId, searchQuery: params.searchQuery);
});

final mangaDetailProvider =
    FutureProvider.autoDispose.family<KsManga, String>((ref, mangaId) async {
  final backend = ref.watch(activeBackendProvider);
  if (backend == null) throw StateError('No active server connection');
  return backend.getMangaDetail(mangaId);
});

final chaptersProvider =
    FutureProvider.autoDispose.family<List<KsChapter>, String>((
  ref,
  mangaId,
) async {
  final backend = ref.watch(activeBackendProvider);
  if (backend == null) return [];
  return backend.getChapters(mangaId);
});

final pagesProvider = FutureProvider.autoDispose.family<List<KsPage>, String>((
  ref,
  chapterId,
) async {
  final backend = ref.watch(activeBackendProvider);
  if (backend == null) return [];
  return backend.getPages(chapterId);
});
