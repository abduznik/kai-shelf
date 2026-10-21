import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/local_notification_presenter.dart';
import '../notifications/notification_controller.dart';
import '../notifications/notification_prefs.dart';
import '../notifications/notification_settings.dart';
import '../notifications/workmanager_check_scheduler.dart';
import '../router/app_router.dart';

/// Whether this build shows the feature at all. Android-first (issue #9):
/// the wiring behind it is Android-only, so desktop and web hide the whole
/// settings section instead of offering a toggle that would do nothing.
final notificationsSupportedProvider = Provider<bool>(
    (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android);

/// The settings as shown in the Settings screen: the toggle plus the check
/// interval. Backed by SharedPreferences; loads itself like the other prefs
/// notifiers, with [NotificationSettingsNotifier.ready] for tests and eager
/// callers.
class NotificationSettingsNotifier extends Notifier<NotificationSettings>
    implements NotificationSettingsStore {
  Future<void>? _loading;

  /// Compleces once the persisted settings have been applied.
  Future<void> get ready => _loading ??= _load();

  @override
  NotificationSettings build() {
    _loading = null;
    ready;
    return const NotificationSettings(
      enabled: false,
      interval: NotificationCheckInterval.defaultInterval,
    );
  }

  Future<void> _load() async {
    state = NotificationSettings(
      enabled: await loadNotificationsEnabled(),
      interval: await loadNotificationInterval(),
    );
  }

  @override
  Future<bool> isEnabled() async {
    await ready;
    return state.enabled;
  }

  @override
  Future<NotificationCheckInterval> interval() async {
    await ready;
    return state.interval;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    await ready;
    state = NotificationSettings(enabled: enabled, interval: state.interval);
    await saveNotificationsEnabled(enabled);
  }

  @override
  Future<void> setInterval(NotificationCheckInterval interval) async {
    await ready;
    state = NotificationSettings(enabled: state.enabled, interval: interval);
    await saveNotificationInterval(interval);
  }
}

final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
        NotificationSettingsNotifier.new);

/// Foreground notification presenter, wired to the router so a tapped
/// notification opens the title it announced. Null where the feature is
/// hidden; initialisation is left to the app startup path so no plugin
/// channel is touched before it is needed (and never at all under tests).
final notificationPresenterProvider =
    Provider<LocalNotificationPresenter?>((ref) {
  if (!ref.watch(notificationsSupportedProvider)) return null;
  return LocalNotificationPresenter(
    onRouteSelected: (route) => appRouter.go(route),
  );
});

/// The controller the Settings screen drives. Null where the feature is
/// hidden — call sites use `?.` and the settings still persist.
final notificationControllerProvider = Provider<NotificationController?>((
  ref,
) {
  if (!ref.watch(notificationsSupportedProvider)) return null;
  final presenter = ref.watch(notificationPresenterProvider);
  return NotificationController(
    settings: ref.read(notificationSettingsProvider.notifier),
    scheduler: WorkmanagerCheckScheduler(),
    permissionGate: presenter,
  );
});
