/// Lower-cases and strips punctuation so "Berserk!" and "berserk" compare
/// equal. Sources and AniList disagree on punctuation far more often than
/// on words.
String normalizeTitle(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

Set<String> _tokens(String normalized) =>
    normalized.split(' ').where((t) => t.isNotEmpty).toSet();

/// Fuzzy "same title" test: equal once normalised, or sharing nearly all
/// words. Plain substring matching is avoided on purpose because it would
/// treat "One Piece Party" as already owned when only "One Piece" is.
bool titlesMatch(String a, String b) {
  final na = normalizeTitle(a);
  final nb = normalizeTitle(b);
  if (na.isEmpty || nb.isEmpty) return false;
  if (na == nb) return true;
  final ta = _tokens(na);
  final tb = _tokens(nb);
  final shared = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  return union > 0 && shared / union >= 0.75;
}
