import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/notifications/notification_controller.dart';
import 'package:kai_shelf/core/notifications/notification_prefs.dart';
import 'package:kai_shelf/core/notifications/notification_settings.dart';
import 'package:kai_shelf/core/providers/notification_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void overridePlatform(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  group('notificationsSupportedProvider', () {
    test('Android has the feature', () {
      overridePlatform(TargetPlatform.android);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(notificationsSupportedProvider), isTrue);
    });

    test('desktop platforms hide it entirely', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ]) {
        overridePlatform(platform);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        expect(container.read(notificationsSupportedProvider), isFalse,
            reason: 'feature must stay hidden on $platform');
      }
    });

    test('iOS is not wired up yet, so it hides the feature too', () {
      overridePlatform(TargetPlatform.iOS);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(notificationsSupportedProvider), isFalse);
    });
  });

  group('NotificationSettingsNotifier', () {
    test('a fresh install starts disabled with the default interval', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(notificationSettingsProvider.notifier).ready;

      final settings = container.read(notificationSettingsProvider);
      expect(settings.enabled, isFalse);
      expect(settings.interval, NotificationCheckInterval.defaultInterval);
    });

    test('the toggle and interval survive a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(notificationSettingsProvider.notifier);
      await notifier.ready;
      await notifier.setEnabled(true);
      await notifier.setInterval(NotificationCheckInterval.sixHours);
      expect(container.read(notificationSettingsProvider).enabled, isTrue);

      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      await restarted.read(notificationSettingsProvider.notifier).ready;
      final settings = restarted.read(notificationSettingsProvider);
      expect(settings.enabled, isTrue);
      expect(settings.interval, NotificationCheckInterval.sixHours);
    });

    test('unsupported platforms have no controller but still persist',
        () async {
      overridePlatform(TargetPlatform.windows);
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(notificationSettingsProvider.notifier);
      await notifier.ready;

      expect(container.read(notificationControllerProvider), isNull);
      await notifier.setEnabled(true);
      expect(await loadNotificationsEnabled(), isTrue);
    });

    test('Android wires a controller that persists through its settings',
        () async {
      overridePlatform(TargetPlatform.android);
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(notificationSettingsProvider.notifier);
      await notifier.ready;

      final controller = container.read(notificationControllerProvider);
      expect(controller, isA<NotificationController>());
      expect(controller!.permissionGate, isNotNull);
      expect(controller.scheduler, isNotNull);
    });
  });
}
