/// User-facing settings for the new-chapter check (issue #9): a single
/// on/off toggle plus how often the background check runs.
library;

/// SharedPreferences keys, shared with the background isolate that reads the
/// same store during a workmanager task.
const notificationsEnabledKey = 'notifications.enabled';
const notificationIntervalMinutesKey = 'notifications.intervalMinutes';

/// How often the background chapter check runs.
///
/// The slowest choices exist for battery: the check touches the server once
/// per tracked title, so a big library on a metered connection wants a long
/// interval. The floor is 30 minutes because Android's WorkManager clamps
/// periodic tasks below 15 minutes anyway.
enum NotificationCheckInterval {
  thirtyMinutes(30, 'Every 30 minutes'),
  hourly(60, 'Hourly'),
  threeHours(180, 'Every 3 hours'),
  sixHours(360, 'Every 6 hours'),
  daily(1440, 'Every 24 hours');

  const NotificationCheckInterval(this.minutes, this.label);

  /// Stored/compared as minutes so the value survives in plain prefs.
  final int minutes;
  final String label;

  Duration get frequency => Duration(minutes: minutes);

  static const NotificationCheckInterval defaultInterval = hourly;

  /// Inverse of [minutes]; anything unknown (older app versions, hand-edited
  /// prefs) falls back to the default instead of breaking the feature.
  static NotificationCheckInterval fromMinutes(int? minutes) => values
      .firstWhere((i) => i.minutes == minutes, orElse: () => defaultInterval);
}

/// The settings as the UI shows them: the toggle plus the interval that only
/// matters while the toggle is on.
class NotificationSettings {
  const NotificationSettings({
    required this.enabled,
    required this.interval,
  });

  final bool enabled;
  final NotificationCheckInterval interval;
}

/// Persistence behind the settings notifier, so controller logic can be
/// tested without SharedPreferences.
abstract class NotificationSettingsStore {
  Future<bool> isEnabled();
  Future<NotificationCheckInterval> interval();
  Future<void> setEnabled(bool enabled);
  Future<void> setInterval(NotificationCheckInterval interval);
}
