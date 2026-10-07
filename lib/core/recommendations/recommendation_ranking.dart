import '../backend/models.dart';
import 'anilist_client.dart';
import 'title_matching.dart';

/// A recommendation merged across every library title that suggested it.
class RankedRecommendation {
  RankedRecommendation(this.recommendation, {this.votes = 0, this.rating = 0});

  final AniListRecommendation recommendation;

  /// How many distinct library titles recommended this.
  int votes;

  /// Sum of AniList's per-pairing ratings across those library titles.
  int rating;
}

/// The library titles worth querying AniList for. The model has no
/// "most read" signal, so recently updated titles stand in for what the
/// user is actively following; the cap keeps the request count small.
List<KsManga> pickSample(List<KsManga> library, {int count = 5}) {
  final sorted = [...library]..sort((a, b) {
      final au = a.lastUpdated, bu = b.lastUpdated;
      if (au == null && bu == null) return 0;
      if (au == null) return 1;
      if (bu == null) return -1;
      return bu.compareTo(au);
    });
  return sorted.take(count).toList();
}

/// Merges per-title recommendation lists into one ranked list, dropping
/// anything the user already owns. Ranked by how many library titles
/// recommend an entry, then summed pairing rating, then AniList score.
List<RankedRecommendation> aggregateRecommendations(
  Iterable<List<AniListRecommendation>> perTitle,
  Iterable<String> libraryTitles, {
  bool allowAdult = false,
}) {
  final owned = libraryTitles.toList();
  final byId = <int, RankedRecommendation>{};
  for (final list in perTitle) {
    // A title can list the same id twice; count each source title once.
    final seen = <int>{};
    for (final rec in list) {
      if (!seen.add(rec.id)) continue;
      if (rec.isAdult && !allowAdult) continue;
      final entry = byId.putIfAbsent(rec.id, () => RankedRecommendation(rec));
      entry.votes += 1;
      entry.rating += rec.rating;
    }
  }
  final result = byId.values
      .where((r) => !r.recommendation.allTitles
          .any((t) => owned.any((o) => titlesMatch(t, o))))
      .toList();
  result.sort((a, b) {
    final byVotes = b.votes.compareTo(a.votes);
    if (byVotes != 0) return byVotes;
    final byRating = b.rating.compareTo(a.rating);
    if (byRating != 0) return byRating;
    return (b.recommendation.averageScore ?? 0)
        .compareTo(a.recommendation.averageScore ?? 0);
  });
  return result;
}
