import '../../../core/backend/models.dart';

enum ExtensionStatus {
  all('All'),
  installed('Installed'),
  updates('Updates'),
  available('Not installed');

  const ExtensionStatus(this.label);
  final String label;
}

/// Client-side filtering for the extension list: the server returns the
/// whole catalog (thousands of entries across repos), so narrowing it by
/// name, install state, language and content rating is done locally.
class ExtensionFilter {
  const ExtensionFilter({
    this.query = '',
    this.status = ExtensionStatus.all,
    this.languages = const {},
    this.hideNsfw = false,
  });

  final String query;
  final ExtensionStatus status;
  final Set<String> languages;
  final bool hideNsfw;

  ExtensionFilter copyWith({
    String? query,
    ExtensionStatus? status,
    Set<String>? languages,
    bool? hideNsfw,
  }) =>
      ExtensionFilter(
        query: query ?? this.query,
        status: status ?? this.status,
        languages: languages ?? this.languages,
        hideNsfw: hideNsfw ?? this.hideNsfw,
      );

  bool matches(KsExtension e) {
    if (e.isObsolete && !e.isInstalled) return false;
    if (hideNsfw && e.contentWarning == ContentWarning.nsfw) return false;
    if (languages.isNotEmpty && !languages.contains(e.lang)) return false;
    switch (status) {
      case ExtensionStatus.all:
        break;
      case ExtensionStatus.installed:
        if (!e.isInstalled) return false;
      case ExtensionStatus.updates:
        if (!e.hasUpdate) return false;
      case ExtensionStatus.available:
        if (e.isInstalled) return false;
    }
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return e.name.toLowerCase().contains(q) ||
        e.pkgName.toLowerCase().contains(q) ||
        (e.lang?.toLowerCase() == q);
  }

  /// Updates first, then installed, then the rest; alphabetical within.
  List<KsExtension> apply(List<KsExtension> all) {
    int rank(KsExtension e) => e.hasUpdate ? 0 : (e.isInstalled ? 1 : 2);
    return all.where(matches).toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0
            ? r
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  static List<String> languagesOf(List<KsExtension> all) {
    final set = {
      for (final e in all)
        if (e.lang != null) e.lang!
    };
    return set.toList()..sort();
  }
}
