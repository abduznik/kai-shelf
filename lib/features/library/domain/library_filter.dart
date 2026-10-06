import '../../../core/backend/models.dart';

enum LibrarySort {
  titleAsc('Title (A–Z)'),
  titleDesc('Title (Z–A)'),
  recentlyUpdated('Recently updated'),
  oldestUpdated('Least recently updated');

  const LibrarySort(this.label);
  final String label;
}

/// Client-side filtering and sorting for the library grid: by title text,
/// publication status, and genres (must-have and must-not-have).
class LibraryFilter {
  const LibraryFilter({
    this.query = '',
    this.statuses = const {},
    this.includeGenres = const {},
    this.excludeGenres = const {},
    this.sort = LibrarySort.titleAsc,
  });

  final String query;
  final Set<MangaStatus> statuses;
  final Set<String> includeGenres;
  final Set<String> excludeGenres;
  final LibrarySort sort;

  /// Number of non-default narrowing options, for a badge on the filter button.
  int get activeCount =>
      (statuses.isEmpty ? 0 : 1) +
      includeGenres.length +
      excludeGenres.length +
      (sort == LibrarySort.titleAsc ? 0 : 1);

  LibraryFilter copyWith({
    String? query,
    Set<MangaStatus>? statuses,
    Set<String>? includeGenres,
    Set<String>? excludeGenres,
    LibrarySort? sort,
  }) =>
      LibraryFilter(
        query: query ?? this.query,
        statuses: statuses ?? this.statuses,
        includeGenres: includeGenres ?? this.includeGenres,
        excludeGenres: excludeGenres ?? this.excludeGenres,
        sort: sort ?? this.sort,
      );

  static String _norm(String g) => g.trim().toLowerCase();

  bool matches(KsManga m) {
    if (statuses.isNotEmpty && !statuses.contains(m.status)) return false;
    final genres = m.genres.map(_norm).toSet();
    if (includeGenres.isNotEmpty &&
        !includeGenres.every((g) => genres.contains(_norm(g)))) {
      return false;
    }
    if (excludeGenres.any((g) => genres.contains(_norm(g)))) return false;
    final q = query.trim().toLowerCase();
    return q.isEmpty || m.title.toLowerCase().contains(q);
  }

  List<KsManga> apply(List<KsManga> all) {
    final result = all.where(matches).toList();
    int byTitle(KsManga a, KsManga b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase());
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    int byUpdated(KsManga a, KsManga b) =>
        (a.lastUpdated ?? epoch).compareTo(b.lastUpdated ?? epoch);
    switch (sort) {
      case LibrarySort.titleAsc:
        result.sort(byTitle);
      case LibrarySort.titleDesc:
        result.sort((a, b) => byTitle(b, a));
      case LibrarySort.recentlyUpdated:
        result.sort((a, b) => byUpdated(b, a));
      case LibrarySort.oldestUpdated:
        result.sort(byUpdated);
    }
    return result;
  }

  /// All distinct genres in the list, with display casing of first sighting.
  static List<String> genresOf(List<KsManga> all) {
    final seen = <String, String>{};
    for (final m in all) {
      for (final g in m.genres) {
        if (g.trim().isNotEmpty) seen.putIfAbsent(_norm(g), () => g.trim());
      }
    }
    return seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}
