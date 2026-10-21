import 'dart:math';

/// Whether the GitHub release tag [latestTag] (e.g. `v1.3.0`) is a newer
/// release than the running [currentVersion] (e.g. `1.2.0+7`).
///
/// Both sides are normalised first: an optional `v`/`V` prefix and the
/// `+build` suffix are dropped, numeric segments compare as numbers so
/// `1.10.0` beats `1.9.9`, and a `-prerelease` suffix ranks below the plain
/// release it precedes (`1.3.0-beta.1` is older than `1.3.0`). Anything that
/// cannot be parsed reports `false`: staying silent beats inventing an
/// update, and a bogus "new version" nag would be worse than missing one.
bool isNewerVersion({
  required String currentVersion,
  required String latestTag,
}) {
  final current = _parseVersion(currentVersion);
  final latest = _parseVersion(latestTag);
  if (current == null || latest == null) return false;
  return latest._compareTo(current) > 0;
}

/// A version reduced to what a release comparison needs: numeric segments
/// plus an optional prerelease suffix (`-beta.1`).
class _Version {
  const _Version(this.segments, this.prerelease);

  final List<int> segments;

  /// Empty for a plain release such as `v1.3.0`.
  final String prerelease;

  int _compareTo(_Version other) {
    final length = max(segments.length, other.segments.length);
    for (var i = 0; i < length; i++) {
      final mine = i < segments.length ? segments[i] : 0;
      final theirs = i < other.segments.length ? other.segments[i] : 0;
      if (mine != theirs) return mine.compareTo(theirs);
    }
    // Same numeric core: the plain release outranks its prereleases.
    if (prerelease.isEmpty && other.prerelease.isNotEmpty) return 1;
    if (prerelease.isNotEmpty && other.prerelease.isEmpty) return -1;
    return prerelease.compareTo(other.prerelease);
  }
}

/// Splits `v1.2.0+7` / `1.3.0-beta.1` into comparable form, or returns null
/// when the input is not a version at all (`nightly`, ``, `1.2.x`).
_Version? _parseVersion(String raw) {
  var value = raw.trim();
  if (value.startsWith('v') || value.startsWith('V')) {
    value = value.substring(1);
  }
  final buildIndex = value.indexOf('+'); // `1.2.0+7`: the build number
  if (buildIndex >= 0) value = value.substring(0, buildIndex);
  var prerelease = '';
  final prereleaseIndex = value.indexOf('-');
  if (prereleaseIndex >= 0) {
    prerelease = value.substring(prereleaseIndex + 1);
    value = value.substring(0, prereleaseIndex);
  }
  if (value.isEmpty) return null;
  final segments = <int>[];
  for (final part in value.split('.')) {
    final segment = int.tryParse(part);
    if (segment == null) return null;
    segments.add(segment);
  }
  return _Version(segments, prerelease);
}
