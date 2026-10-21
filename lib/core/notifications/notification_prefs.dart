import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'chapter_check_engine.dart';
import 'notification_settings.dart';

/// SharedPreferences-backed reads, usable from the background isolate where
/// there is no settings notifier to ask. Unreadable storage never throws:
/// each getter falls back to the same defaults the notifier starts from.

Future<bool> loadNotificationsEnabled() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(notificationsEnabledKey) ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> saveNotificationsEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(notificationsEnabledKey, enabled);
}

Future<NotificationCheckInterval> loadNotificationInterval() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return NotificationCheckInterval.fromMinutes(
        prefs.getInt(notificationIntervalMinutesKey));
  } catch (_) {
    return NotificationCheckInterval.defaultInterval;
  }
}

Future<void> saveNotificationInterval(
    NotificationCheckInterval interval) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(notificationIntervalMinutesKey, interval.minutes);
}

/// The settings store behind the settings notifier.
class PrefsNotificationSettingsStore implements NotificationSettingsStore {
  @override
  Future<bool> isEnabled() => loadNotificationsEnabled();

  @override
  Future<NotificationCheckInterval> interval() => loadNotificationInterval();

  @override
  Future<void> setEnabled(bool enabled) => saveNotificationsEnabled(enabled);

  @override
  Future<void> setInterval(NotificationCheckInterval interval) =>
      saveNotificationInterval(interval);
}

/// Where the per-title high-water marks live: one JSON blob of
/// `{mangaId: newestChapterNumber}`, readable from the foreground UI and the
/// background check alike.
const notificationHighWaterMarksKey = 'notifications.highWaterMarks';

class PrefsHighWaterMarkStore implements HighWaterMarkStore {
  @override
  Future<Map<String, double>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(notificationHighWaterMarksKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final marks = <String, double>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (entry.key is! String || value is! num || value.isNaN) continue;
        marks[entry.key as String] = value.toDouble();
      }
      return marks;
    } catch (_) {
      // Unreadable storage must never crash a background check; the marks
      // simply re-baseline on the next run.
      return {};
    }
  }

  @override
  Future<void> save(Map<String, double> marks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(notificationHighWaterMarksKey, jsonEncode(marks));
  }
}
