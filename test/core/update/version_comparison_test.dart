import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/update/version_comparison.dart';

/// Version comparison for the GitHub release check (#14). The running app
/// reports `1.2.0+7` (pubspec `version:`) while release tags look like
/// `v1.2.0`, so the `v` prefix and the `+build` suffix must never make a
/// release look newer — or hide one that actually is.
void main() {
  group('isNewerVersion', () {
    test('the build suffix never makes a release look newer', () {
      expect(isNewerVersion(currentVersion: '1.2.0+7', latestTag: 'v1.2.0'),
          isFalse);
      expect(isNewerVersion(currentVersion: '1.2.0+7', latestTag: '1.2.0'),
          isFalse);
    });

    test('a newer release tag is detected through the build suffix', () {
      expect(isNewerVersion(currentVersion: '1.2.0+7', latestTag: 'v1.2.1'),
          isTrue);
      expect(isNewerVersion(currentVersion: '1.3.0+8', latestTag: 'v1.4.0'),
          isTrue);
    });

    test('an older release tag is not an update', () {
      expect(isNewerVersion(currentVersion: '1.2.0+7', latestTag: 'v1.1.9'),
          isFalse);
      expect(isNewerVersion(currentVersion: '1.3.0+8', latestTag: 'v1.2.0'),
          isFalse);
    });

    test('segments compare numerically, not lexicographically', () {
      expect(isNewerVersion(currentVersion: '1.9.9', latestTag: 'v1.10.0'),
          isTrue);
      expect(isNewerVersion(currentVersion: '9.0.0', latestTag: 'v10.0.0'),
          isTrue);
      expect(isNewerVersion(currentVersion: '1.10.0', latestTag: 'v1.9.9'),
          isFalse);
    });

    test('a prerelease tag is older than the same released version', () {
      expect(
          isNewerVersion(
              currentVersion: '1.3.0+10', latestTag: 'v1.3.0-beta.1'),
          isFalse);
      expect(
          isNewerVersion(currentVersion: '1.2.0+7', latestTag: 'v1.3.0-beta.1'),
          isTrue);
    });

    test('versions without a v prefix or build suffix work', () {
      expect(
          isNewerVersion(currentVersion: '1.2.0', latestTag: '1.2.1'), isTrue);
      expect(
          isNewerVersion(currentVersion: '1.2.0', latestTag: '1.2.0'), isFalse);
      expect(isNewerVersion(currentVersion: '1.2.0', latestTag: 'v1.2.0+42'),
          isFalse);
    });

    test('unparseable input never reports an update', () {
      expect(isNewerVersion(currentVersion: '', latestTag: 'v1.3.0'), isFalse);
      expect(isNewerVersion(currentVersion: '1.2.0+7', latestTag: ''), isFalse);
      expect(isNewerVersion(currentVersion: '1.2.0+7', latestTag: 'nightly'),
          isFalse);
      expect(
          isNewerVersion(currentVersion: 'not-a-version', latestTag: 'v1.3.0'),
          isFalse);
    });
  });
}
