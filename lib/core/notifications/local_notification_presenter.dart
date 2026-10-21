import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'chapter_check_engine.dart';
import 'notification_controller.dart';

/// Real, platform-backed presenter: one Android notification channel for
/// new chapters, one notification per title (re-posted, not stacked, when
/// the same title gains more chapters later), payload = the app route a tap
/// should open.
///
/// Used from both the foreground app and the workmanager background isolate,
/// which is why every entry point starts with the lazy, retry-on-failure
/// [ensureInitialised]: the two isolates initialise independently and a
/// failed attempt (plugin not ready yet) must not poison later calls.
class LocalNotificationPresenter
    implements NotificationPresenter, NotificationPermissionGate {
  LocalNotificationPresenter({void Function(String route)? onRouteSelected})
      : _onRouteSelected = onRouteSelected;

  static const channelId = 'new_chapters';
  static const channelName = 'New chapters';
  static const channelDescription =
      'Alerts when a title in your library gets new chapters';

  final void Function(String route)? _onRouteSelected;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<bool?>? _initialising;

  Future<bool?> ensureInitialised() =>
      _initialising ??= _initialise().catchError((Object _) => false);

  Future<bool?> _initialise() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    final initialised = await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.startsWith('/')) {
          _onRouteSelected?.call(payload);
        }
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.high,
        ));
    return initialised;
  }

  @override
  Future<bool?> requestPermission() async {
    await ensureInitialised();
    return _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  @override
  Future<void> show(NewChapterNotification notification) async {
    await ensureInitialised();
    await _plugin.show(
      // Stable per title: a second alert for the same manga replaces the
      // first instead of stacking an endless column.
      id: notification.mangaId.hashCode & 0x7fffffff,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: notification.route,
    );
  }

  /// The route encoded in the notification that launched a cold-started app,
  /// or null when the app was opened normally. Validated against the route
  /// shapes this feature ever writes, so a stale or foreign payload cannot
  /// steer the router somewhere unintended.
  Future<String?> consumeLaunchRoute() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      final payload = details.notificationResponse?.payload;
      if (payload == null || !payload.startsWith('/manga/')) return null;
      return payload;
    } catch (_) {
      return null;
    }
  }
}
