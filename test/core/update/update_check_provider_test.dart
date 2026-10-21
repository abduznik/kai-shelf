import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/providers/app_version_provider.dart';
import 'package:kai_shelf/core/update/update_check_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Update check against GitHub releases (#14): throttled, cached, and silent
/// on every failure path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const releaseUrl =
      'https://github.com/abduznik/kai-shelf/releases/tag/v1.3.0';

  String releaseBody(String tag) =>
      '{"tag_name": "$tag", "html_url": "$releaseUrl"}';

  PackageInfo packageInfo({String version = '1.2.0', String build = '7'}) =>
      PackageInfo(
        appName: 'Kai-Shelf',
        packageName: 'kai_shelf',
        version: version,
        buildNumber: build,
        buildSignature: '',
      );

  ProviderContainer containerWith(MockClient client, {String build = '7'}) {
    final container = ProviderContainer(
      overrides: [
        updateHttpClientProvider.overrideWithValue(client),
        packageInfoProvider.overrideWith((_) => packageInfo(build: build)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> ageLastCheckByTwoDays() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      updateLastCheckedPrefKey,
      DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a newer release is detected and handed to the UI', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.toString(), updateCheckUrl);
      return http.Response(releaseBody('v1.3.0'), 200);
    });
    final container = containerWith(client);

    await container.read(updateCheckProvider.notifier).check();

    expect(calls, 1);
    final state = container.read(updateCheckProvider);
    expect(state.latestTag, 'v1.3.0');
    expect(state.releaseUrl, releaseUrl);
    expect(state.updateAvailable, isTrue,
        reason: '1.3.0 is newer than the running 1.2.0+7');
    final availability = container.read(updateAvailabilityProvider);
    expect(availability?.tag, 'v1.3.0');
    expect(availability?.releaseUrl, releaseUrl);
    expect(container.read(updatePromptProvider), isNotNull);
  });

  test('an equal release tag is not an update, build suffix included',
      () async {
    final client = MockClient(
      (_) async => http.Response(releaseBody('v1.2.0'), 200),
    );
    final container = containerWith(client);

    await container.read(updateCheckProvider.notifier).check();

    expect(container.read(updateCheckProvider).latestTag, 'v1.2.0');
    expect(container.read(updateCheckProvider).updateAvailable, isFalse,
        reason: '1.2.0+7 and v1.2.0 are the same release');
    expect(container.read(updateAvailabilityProvider), isNull);
    expect(container.read(updatePromptProvider), isNull);
  });

  test('at most one network check per day', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(releaseBody('v1.3.0'), 200);
    });
    final container = containerWith(client);
    final notifier = container.read(updateCheckProvider.notifier);

    await notifier.check();
    await notifier.check();
    expect(calls, 1, reason: 'the second call is served from the cache');

    await ageLastCheckByTwoDays();
    await notifier.check();
    expect(calls, 2, reason: 'a day later the budget refills');
  });

  test('a cached result is reused without any network request', () async {
    SharedPreferences.setMockInitialValues({
      updateLatestTagPrefKey: 'v1.3.0',
      updateReleaseUrlPrefKey: 'https://example.com/v1.3.0',
      updateLastCheckedPrefKey: DateTime.now().millisecondsSinceEpoch,
    });
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(releaseBody('v1.3.0'), 200);
    });
    final container = containerWith(client);

    await container.read(updateCheckProvider.notifier).check();

    expect(calls, 0, reason: "today's check already happened");
    expect(container.read(updateCheckProvider).latestTag, 'v1.3.0');
    expect(container.read(updateAvailabilityProvider)?.releaseUrl,
        'https://example.com/v1.3.0');
  });

  test('network failure is silent, keeps what is known, spends a day',
      () async {
    var calls = 0;
    var failing = false;
    final client = MockClient((_) async {
      calls++;
      if (failing) throw http.ClientException('offline');
      return http.Response(releaseBody('v1.3.0'), 200);
    });
    final container = containerWith(client);
    final notifier = container.read(updateCheckProvider.notifier);

    await notifier.check();
    expect(calls, 1);

    await ageLastCheckByTwoDays();
    failing = true;

    await notifier.check(); // must not throw, must not change the outcome
    expect(calls, 2);
    expect(container.read(updateCheckProvider).latestTag, 'v1.3.0',
        reason: 'the last good result keeps standing in');
    expect(container.read(updateAvailabilityProvider)?.tag, 'v1.3.0');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt(updateLastCheckedPrefKey)!,
      greaterThan(
        DateTime.now()
            .subtract(const Duration(hours: 23))
            .millisecondsSinceEpoch,
      ),
      reason: 'the failed attempt still spends the daily budget',
    );

    // And the next call inside the window does not touch the network again.
    await notifier.check();
    expect(calls, 2);
  });

  test('a non-200 answer is a non-event, not an error', () async {
    final client = MockClient((_) async => http.Response('rate limited', 500));
    final container = containerWith(client);

    await container.read(updateCheckProvider.notifier).check();

    expect(container.read(updateCheckProvider).latestTag, isNull);
    expect(container.read(updateAvailabilityProvider), isNull);
    expect(container.read(updatePromptProvider), isNull);
  });

  test('a malformed payload is a non-event, not an error', () async {
    final client = MockClient((_) async => http.Response('{"nope": 1}', 200));
    final container = containerWith(client);

    await container.read(updateCheckProvider.notifier).check();

    expect(container.read(updateCheckProvider).latestTag, isNull);
    expect(container.read(updateAvailabilityProvider), isNull);
  });

  test('"Later" retires the prompt for that version, and only for it',
      () async {
    var tag = 'v1.3.0';
    final client = MockClient(
      (_) async => http.Response(releaseBody(tag), 200),
    );
    final container = containerWith(client);
    final notifier = container.read(updateCheckProvider.notifier);

    await notifier.check();
    await container
        .read(suppressedUpdateTagProvider.notifier)
        .suppress('v1.3.0');
    expect(container.read(updatePromptProvider), isNull,
        reason: 'the prompt never returns for that version');
    expect(container.read(updateAvailabilityProvider), isNotNull,
        reason: 'the quiet settings row stays');

    // A later check with the same tag does not nag again.
    await ageLastCheckByTwoDays();
    await notifier.check();
    expect(container.read(updatePromptProvider), isNull);

    // A newer release re-arms the prompt.
    tag = 'v1.4.0';
    await ageLastCheckByTwoDays();
    await notifier.check();
    expect(container.read(updatePromptProvider)?.tag, 'v1.4.0');
    expect(container.read(updateAvailabilityProvider)?.tag, 'v1.4.0');

    // The suppression itself survives a restart.
    SharedPreferences.setMockInitialValues(
        {updateSuppressedTagPrefKey: 'v1.3.0'});
    final restarted = containerWith(client);
    await restarted.read(suppressedUpdateTagProvider.notifier).ready;
    expect(restarted.read(suppressedUpdateTagProvider), 'v1.3.0');
  });

  test('a cache written by an earlier run is picked up silently', () async {
    SharedPreferences.setMockInitialValues({
      updateLatestTagPrefKey: 'v1.4.0',
      updateReleaseUrlPrefKey: releaseUrl,
      updateLastCheckedPrefKey: DateTime.now().millisecondsSinceEpoch,
    });
    final client = MockClient(
      (_) async => http.Response(releaseBody('v1.4.0'), 200),
    );
    final container = containerWith(client, build: '7');

    await container.read(updateCheckProvider.notifier).ready;

    final state = container.read(updateCheckProvider);
    expect(state.latestTag, 'v1.4.0');
    expect(state.updateAvailable, isTrue);
    expect(state.lastCheckedAt, isNotNull);
  });
}
