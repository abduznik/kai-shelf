import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../recommendations/anilist_client.dart';
import '../recommendations/recommendation_ranking.dart';
import 'backend_providers.dart';

/// One client for the app's lifetime so its cache and rate window are shared
/// by every screen.
final aniListClientProvider = Provider<AniListClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return AniListClient(httpClient: client);
});

/// Recommendations for one title. Never errors: the client maps failures to
/// an empty list, and its own cache stops the detail screen re-querying
/// when revisited.
final titleRecommendationsProvider =
    FutureProvider.family<List<AniListRecommendation>, String>((ref, title) =>
        ref.watch(aniListClientProvider).recommendationsFor(title));

/// Library-wide recommendations, kept for the session (not autoDispose) so
/// leaving and re-entering the screen costs nothing. The refresh button
/// clears the client cache and invalidates this.
final libraryRecommendationsProvider =
    FutureProvider<List<RankedRecommendation>>((ref) async {
  final backend = ref.watch(activeBackendProvider);
  if (backend == null) return [];
  final library = await backend.getAllManga();
  if (library.isEmpty) return [];
  final client = ref.watch(aniListClientProvider);
  final sample = pickSample(library);
  final lists = await Future.wait([
    for (final m in sample) client.recommendationsFor(m.title, perPage: 15)
  ]);
  return aggregateRecommendations(lists, [for (final m in library) m.title]);
});
