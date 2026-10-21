import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The app's own package metadata. A FutureProvider so consumers handle the
/// brief loading state themselves and a failed platform lookup stays a
/// non-event instead of an error dialog.
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// The version spelled the way the settings row and the update check both
/// need it: `1.2.0+7` (pubspec `version: 1.2.0+7`).
String formatAppVersion(PackageInfo info) =>
    '${info.version}+${info.buildNumber}';
