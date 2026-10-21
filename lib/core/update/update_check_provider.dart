import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_version_provider.dart';
import 'version_comparison.dart';

/// Latest published release of this repo, as GitHub's public API serves it.
const updateCheckUrl =
    'https://api.github.com/repos/abduznik/kai-shelf/releases/latest';

/// Where every update surface sends the user: downloads stay on GitHub,
/// outside the app, so there is no auto-update machinery to maintain.
const releasesPageUrl = 'https://github.com/abduznik/kai-shelf/releases';

/// Hard budget for the network: at most one check per day, cached otherwise.
const updateCheckInterval = Duration(days: 1);

const updateLastCheckedPrefKey = 'update.lastCheckedAt';
const updateLatestTagPrefKey = 'update.latestTag';
const updateReleaseUrlPrefKey = 'update.releaseUrl';
const updateSuppressedTagPrefKey = 'update.suppressedTag';

/// The HTTP client the update check runs on. Injectable so tests never touch
/// the network, and disposed with the container that created it.
final updateHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// What the last (successful or not) check left behind. [updateAvailable] is
/// resolved when the result is published: latest release tag versus the
/// running `1.2.0+7`.
class UpdateCheckState {
  const UpdateCheckState({
    this.latestTag,
    this.releaseUrl,
    this.lastCheckedAt,
    this.updateAvailable = false,
  });

  static const empty = UpdateCheckState();

  final String? latestTag;
  final String? releaseUrl;
  final DateTime? lastCheckedAt;
  final bool updateAvailable;
}

/// A newer release the user has not suppressed yet.
class UpdateAvailability {
  const UpdateAvailability({required this.tag, required this.releaseUrl});

  final String tag;
  final String releaseUrl;
}

/// Queries GitHub for the latest release, at most once per
/// [updateCheckInterval], and remembers the answer across restarts.
///
/// Every failure path is silent by contract: no throw, no error state, no
/// dialog — a blocked, rate-limited or offline network simply leaves
/// whatever was already known in place. Nothing here blocks startup: main()
/// and Settings both fire-and-forget [UpdateCheckNotifier.check].
class UpdateCheckNotifier extends Notifier<UpdateCheckState> {
  Future<void>? _loading;

  /// Restores the cached result without touching the network.
  Future<void> get ready => _loading ??= _restore();

  @override
  UpdateCheckState build() {
    _loading = null;
    ready;
    return UpdateCheckState.empty;
  }

  /// Checks GitHub for a newer release. Safe to call from anywhere: it is a
  /// no-op while today's check already happened (unless [force]).
  Future<void> check({bool force = false}) async {
    try {
      await ready;
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      if (!force && _checkedRecently(prefs, now)) return;
      try {
        final response = await ref
            .read(updateHttpClientProvider)
            .get(Uri.parse(updateCheckUrl), headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'kai-shelf',
        }).timeout(const Duration(seconds: 10));
        final release = _releaseFrom(response);
        await _publish(
          tag: release.tag,
          releaseUrl: release.url,
          checkedAt: now,
        );
        await prefs.setString(updateLatestTagPrefKey, release.tag);
        await prefs.setString(updateReleaseUrlPrefKey, release.url);
      } catch (_) {
        // Silent by design: the cached result (if any) keeps standing in.
      }
      // The attempt is remembered either way, so a network that is down all
      // day still costs at most one request per day.
      await prefs.setInt(
        updateLastCheckedPrefKey,
        now.millisecondsSinceEpoch,
      );
    } catch (_) {
      // Unreadable storage or a torn-down container: nothing to update, and
      // an update check must never break the app around it.
    }
  }

  bool _checkedRecently(SharedPreferences prefs, DateTime now) {
    final last = prefs.getInt(updateLastCheckedPrefKey);
    if (last == null) return false;
    final checkedAt = DateTime.fromMillisecondsSinceEpoch(last);
    return now.difference(checkedAt) < updateCheckInterval;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(updateLastCheckedPrefKey);
      final checkedAt =
          last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
      final tag = prefs.getString(updateLatestTagPrefKey);
      if (tag == null || tag.isEmpty) {
        if (checkedAt != null) {
          try {
            state = UpdateCheckState(lastCheckedAt: checkedAt);
          } catch (_) {
            // Container disposed while storage was being read.
          }
        }
        return;
      }
      await _publish(
        tag: tag,
        releaseUrl: prefs.getString(updateReleaseUrlPrefKey) ?? releasesPageUrl,
        checkedAt: checkedAt,
      );
    } catch (_) {
      // Nothing cached: the first check simply starts from scratch.
    }
  }

  Future<void> _publish({
    required String tag,
    required String releaseUrl,
    required DateTime? checkedAt,
  }) async {
    final available = await _isNewerRelease(tag);
    try {
      state = UpdateCheckState(
        latestTag: tag,
        releaseUrl: releaseUrl,
        lastCheckedAt: checkedAt,
        updateAvailable: available,
      );
    } catch (_) {
      // Container disposed mid-read; there is no state left to publish to.
    }
  }

  Future<bool> _isNewerRelease(String tag) async {
    try {
      final info = await ref.read(packageInfoProvider.future);
      return isNewerVersion(
        currentVersion: '${info.version}+${info.buildNumber}',
        latestTag: tag,
      );
    } catch (_) {
      // Running version unknown: never claim an update.
      return false;
    }
  }

  /// Pulls the tag and release URL out of GitHub's response; anything
  /// unexpected throws so the caller treats it exactly like a network
  /// failure.
  ({String tag, String url}) _releaseFrom(http.Response response) {
    if (response.statusCode != 200) {
      throw http.ClientException('release lookup failed: '
          'HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('release payload is not an object');
    }
    final tag = decoded['tag_name'];
    if (tag is! String || tag.isEmpty) {
      throw const FormatException('release payload has no tag_name');
    }
    final htmlUrl = decoded['html_url'];
    return (
      tag: tag,
      url: htmlUrl is String && htmlUrl.isNotEmpty ? htmlUrl : releasesPageUrl,
    );
  }
}

final updateCheckProvider =
    NotifierProvider<UpdateCheckNotifier, UpdateCheckState>(
  UpdateCheckNotifier.new,
);

/// The release the user dismissed with "Later": it never prompts again, and
/// only a newer release can re-arm the prompt.
class SuppressedTagNotifier extends Notifier<String?> {
  Future<void>? _loading;

  /// Completes once the suppressed tag has been read from storage.
  Future<void> get ready => _loading ??= _load();

  @override
  String? build() {
    _loading = null;
    ready;
    return null;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getString(updateSuppressedTagPrefKey);
    } catch (_) {
      // No readable preference: treat as "nothing suppressed".
    }
  }

  Future<void> suppress(String tag) async {
    await ready;
    state = tag;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(updateSuppressedTagPrefKey, tag);
    } catch (_) {
      // Not persisting only means the prompt returns after a restart.
    }
  }
}

final suppressedUpdateTagProvider =
    NotifierProvider<SuppressedTagNotifier, String?>(
  SuppressedTagNotifier.new,
);

/// The quiet settings row: shown while a newer release than the running
/// version is known, whatever the user thought of the prompt.
final updateAvailabilityProvider = Provider<UpdateAvailability?>((ref) {
  final state = ref.watch(updateCheckProvider);
  final tag = state.latestTag;
  if (!state.updateAvailable || tag == null) return null;
  return UpdateAvailability(
    tag: tag,
    releaseUrl: state.releaseUrl ?? releasesPageUrl,
  );
});

/// The dismissible prompt: [updateAvailabilityProvider] minus whatever the
/// user already dismissed.
final updatePromptProvider = Provider<UpdateAvailability?>((ref) {
  final available = ref.watch(updateAvailabilityProvider);
  if (available == null) return null;
  if (available.tag == ref.watch(suppressedUpdateTagProvider)) return null;
  return available;
});
