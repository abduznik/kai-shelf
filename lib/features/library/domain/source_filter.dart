import '../../../core/backend/models.dart';

/// Client-side narrowing of the installed-source list.
class SourceListFilter {
  const SourceListFilter({
    this.query = '',
    this.languages = const {},
    this.hideNsfw = false,
  });

  final String query;
  final Set<String> languages;
  final bool hideNsfw;

  SourceListFilter copyWith(
          {String? query, Set<String>? languages, bool? hideNsfw}) =>
      SourceListFilter(
        query: query ?? this.query,
        languages: languages ?? this.languages,
        hideNsfw: hideNsfw ?? this.hideNsfw,
      );

  bool matches(KsSource s) {
    if (hideNsfw && s.contentWarning == ContentWarning.nsfw) return false;
    if (languages.isNotEmpty && !languages.contains(s.lang)) return false;
    final q = query.trim().toLowerCase();
    return q.isEmpty || s.label.toLowerCase().contains(q);
  }

  List<KsSource> apply(List<KsSource> all) => all.where(matches).toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  static List<String> languagesOf(List<KsSource> all) {
    final set = {
      for (final s in all)
        if (s.lang != null) s.lang!
    };
    return set.toList()..sort();
  }
}
