import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/notifications/notification_controller.dart';
import 'package:kai_shelf/core/notifications/notification_settings.dart';

import 'notification_test_support.dart';

void main() {
  group('NotificationController', () {
    test('enabling asks for permission and schedules the stored interval',
        () async {
      final settings = FakeSettingsStore(
        interval: NotificationCheckInterval.threeHours,
      );
      final scheduler = FakeScheduler();
      final gate = FakePermissionGate();
      final controller = NotificationController(
        settings: settings,
        scheduler: scheduler,
        permissionGate: gate,
      );

      await controller.setEnabled(true);

      expect(gate.requestCalls, 1);
      expect(scheduler.scheduled, [const Duration(hours: 3)]);
      expect(await settings.isEnabled(), isTrue);
    });

    test('a refused permission schedules nothing', () async {
      final scheduler = FakeScheduler();
      final controller = NotificationController(
        settings: FakeSettingsStore(),
        scheduler: scheduler,
        permissionGate: FakePermissionGate(granted: false),
      );

      await controller.setEnabled(true);

      expect(scheduler.scheduled, isEmpty);
      // The preference is still on, so the settings UI reflects reality and
      // the user can re-ask by toggling again.
      expect(await controller.settings.isEnabled(), isTrue);
    });

    test('disabling cancels the schedule', () async {
      final scheduler = FakeScheduler();
      final controller = NotificationController(
        settings: FakeSettingsStore(enabled: true),
        scheduler: scheduler,
        permissionGate: FakePermissionGate(),
      );

      await controller.setEnabled(false);

      expect(scheduler.cancelCalls, 1);
      expect(scheduler.scheduled, isEmpty);
    });

    test('start leaves an untouched install alone', () async {
      final scheduler = FakeScheduler();
      final controller = NotificationController(
        settings: FakeSettingsStore(enabled: false),
        scheduler: scheduler,
        permissionGate: FakePermissionGate(),
      );

      await controller.start();

      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelCalls, 0);
    });

    test('start re-arms the schedule of an already-enabled install', () async {
      final scheduler = FakeScheduler();
      final controller = NotificationController(
        settings: FakeSettingsStore(
          enabled: true,
          interval: NotificationCheckInterval.daily,
        ),
        scheduler: scheduler,
        permissionGate: FakePermissionGate(),
      );

      await controller.start();

      expect(scheduler.scheduled, [const Duration(days: 1)]);
    });

    test('changing the interval while enabled reschedules', () async {
      final scheduler = FakeScheduler();
      final controller = NotificationController(
        settings: FakeSettingsStore(enabled: true),
        scheduler: scheduler,
        permissionGate: FakePermissionGate(),
      );

      await controller.setInterval(NotificationCheckInterval.sixHours);

      expect(scheduler.scheduled, [const Duration(hours: 6)]);
    });

    test('changing the interval while disabled schedules nothing', () async {
      final scheduler = FakeScheduler();
      final controller = NotificationController(
        settings: FakeSettingsStore(enabled: false),
        scheduler: scheduler,
        permissionGate: FakePermissionGate(),
      );

      await controller.setInterval(NotificationCheckInterval.sixHours);

      expect(scheduler.scheduled, isEmpty);
    });

    test('without platform support the settings still persist', () async {
      final settings = FakeSettingsStore();
      final controller = NotificationController(settings: settings);

      await controller.setEnabled(true);
      await controller.setInterval(NotificationCheckInterval.daily);
      await controller.start();

      expect(await settings.isEnabled(), isTrue);
      expect(await settings.interval(), NotificationCheckInterval.daily);
    });

    test('a broken platform plugin never breaks the toggle', () async {
      final settings = FakeSettingsStore();
      final scheduler = FakeScheduler()..throwOnSchedule = true;
      final gate = FakePermissionGate()..throwOnRequest = true;
      final controller = NotificationController(
        settings: settings,
        scheduler: scheduler,
        permissionGate: gate,
      );

      // Both platform calls explode, like they would on a device where the
      // plugin or WorkManager is unavailable.
      await controller.setEnabled(true);
      await controller.setInterval(NotificationCheckInterval.daily);
      await controller.start();

      expect(await settings.isEnabled(), isTrue);
      expect(scheduler.scheduled, isEmpty);
    });

    test('a broken cancel never breaks switching off', () async {
      final controller = NotificationController(
        settings: FakeSettingsStore(enabled: true),
        scheduler: _ThrowingCancelScheduler(),
        permissionGate: FakePermissionGate(),
      );

      await controller.setEnabled(false);

      expect(await controller.settings.isEnabled(), isFalse);
    });
  });
}

class _ThrowingCancelScheduler implements CheckScheduler {
  @override
  Future<void> schedulePeriodic(Duration interval) async {}

  @override
  Future<void> cancel() => throw StateError('workmanager unavailable');
}
