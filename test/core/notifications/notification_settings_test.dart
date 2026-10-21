import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/notifications/notification_prefs.dart';
import 'package:kai_shelf/core/notifications/notification_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationCheckInterval', () {
    test('an unknown stored value falls back to the default', () {
      expect(NotificationCheckInterval.fromMinutes(999),
          NotificationCheckInterval.defaultInterval);
      expect(NotificationCheckInterval.fromMinutes(null),
          NotificationCheckInterval.defaultInterval);
    });

    test('a known stored value parses back exactly', () {
      expect(NotificationCheckInterval.fromMinutes(180),
          NotificationCheckInterval.threeHours);
      expect(NotificationCheckInterval.threeHours.frequency,
          const Duration(hours: 3));
    });

    test('the default is an hourly check', () {
      expect(NotificationCheckInterval.defaultInterval,
          NotificationCheckInterval.hourly);
    });
  });

  group('PrefsNotificationSettingsStore', () {
    test('a fresh install is disabled and hourly', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PrefsNotificationSettingsStore();

      expect(await store.isEnabled(), isFalse);
      expect(await store.interval(), NotificationCheckInterval.hourly);
    });

    test('the toggle and interval survive a restart', () async {
      SharedPreferences.setMockInitialValues({});
      await PrefsNotificationSettingsStore().setEnabled(true);
      await PrefsNotificationSettingsStore()
          .setInterval(NotificationCheckInterval.daily);

      final restarted = PrefsNotificationSettingsStore();
      expect(await restarted.isEnabled(), isTrue);
      expect(await restarted.interval(), NotificationCheckInterval.daily);
    });
  });

  group('PrefsHighWaterMarkStore', () {
    test('marks round-trip through preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PrefsHighWaterMarkStore();

      await store.save({'m1': 12.5, 'm2': 3.0});
      expect(await store.load(), {'m1': 12.5, 'm2': 3.0});
    });

    test('unreadable stored data degrades to an empty map', () async {
      SharedPreferences.setMockInitialValues({
        notificationHighWaterMarksKey: 'not json',
      });

      expect(await PrefsHighWaterMarkStore().load(), isEmpty);
    });
  });
}
