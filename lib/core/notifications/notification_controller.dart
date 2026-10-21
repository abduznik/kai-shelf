import 'chapter_check_engine.dart';
import 'notification_settings.dart';

/// Registers (and cancels) the periodic background chapter check. Behind an
/// interface because scheduling goes through platform channels, which do not
/// exist under `flutter test`.
abstract class CheckScheduler {
  Future<void> schedulePeriodic(Duration interval);
  Future<void> cancel();
}

/// Asks Android 13+ for POST_NOTIFICATIONS. Split from
/// [NotificationPresenter] so the engine's presenter interface stays the
/// one thing the engine needs, while the controller can still gate
/// scheduling on the user's answer.
abstract class NotificationPermissionGate {
  Future<bool?> requestPermission();
}

/// Everything the settings UI does to the platform: flip the toggle, change
/// the interval, and bring the schedule in line with the stored settings at
/// startup. Pure Dart — the platform pieces arrive as interfaces, so every
/// branch here is unit-tested with fakes.
class NotificationController {
  const NotificationController({
    required this.settings,
    this.scheduler,
    this.permissionGate,
  });

  final NotificationSettingsStore settings;

  /// Null on platforms where the feature is hidden (desktop/web).
  final CheckScheduler? scheduler;
  final NotificationPermissionGate? permissionGate;

  /// Called once when the app starts: re-arms the periodic task so an
  /// already-enabled install keeps checking after an app update or reboot,
  /// and does nothing at all on a fresh, disabled install.
  ///
  /// Platform calls are best-effort throughout: a missing plugin or an
  /// unavailable WorkManager must never surface as an error in the app —
  /// the worst outcome is a check that does not run until the next attempt.
  Future<void> start() async {
    if (scheduler == null) return;
    if (!await settings.isEnabled()) return;
    try {
      await scheduler!.schedulePeriodic((await settings.interval()).frequency);
    } catch (_) {}
  }

  /// Applies the toggle. Enabling first persists the choice, then asks for
  /// the notification permission and only schedules the background check
  /// when there is one to show — a denied permission never leaves silent
  /// background work running against the server.
  Future<void> setEnabled(bool enabled) async {
    await settings.setEnabled(enabled);
    try {
      if (!enabled) {
        await scheduler?.cancel();
        return;
      }
      if (scheduler == null) return;
      final granted = await permissionGate?.requestPermission();
      if (granted == false) return;
      await scheduler!.schedulePeriodic((await settings.interval()).frequency);
    } catch (_) {}
  }

  /// Persists a new interval and, if checks are currently on, re-registers
  /// the task so the change takes effect without waiting for a restart.
  Future<void> setInterval(NotificationCheckInterval interval) async {
    await settings.setInterval(interval);
    if (scheduler == null) return;
    try {
      if (!await settings.isEnabled()) return;
      await scheduler!.schedulePeriodic(interval.frequency);
    } catch (_) {}
  }
}
