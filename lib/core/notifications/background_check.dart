import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../providers/backend_providers.dart';
import '../providers/incognito_provider.dart';
import '../storage/session_store.dart';
import 'backend_chapter_catalog.dart';
import 'local_notification_presenter.dart';
import 'notification_check_runner.dart';
import 'notification_prefs.dart';

/// Task identifiers. The unique name is what WorkManager keys the single
/// scheduled periodic task by (one task, re-registered, never stacked); the
/// task name is what the dispatcher below matches on.
const newChapterCheckTaskName = 'newChapterCheck';
const newChapterCheckUniqueName = 'com.abduznik.kai_shelf.new_chapter_check';

/// WorkManager's entry point, invoked in a fresh background isolate whenever
/// the periodic task is due — the app does not need to be running.
@pragma('vm:entry-point')
void notificationCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != newChapterCheckTaskName) return true;
    await runBackgroundChapterCheck();
    return true;
  });
}

/// One background chapter check with the production wiring: stored settings
/// and incognito flag from SharedPreferences, the saved session from secure
/// storage, the active backend adapter, and local notifications for output.
///
/// The skip paths run *before* any session or network work, so a disabled
/// feature costs nothing at all — the same guarantee the unit tests pin
/// down via [runChapterCheck].
@pragma('vm:entry-point')
Future<NotificationCheckOutcome> runBackgroundChapterCheck() async {
  final presenter = LocalNotificationPresenter();
  return runChapterCheck(
    enabled: loadNotificationsEnabled,
    incognito: () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getBool(incognitoPrefKey) ?? false;
      } catch (_) {
        return false;
      }
    },
    catalog: () async {
      final container = ProviderContainer();
      final connection = await SessionStore().load();
      if (connection == null) {
        container.dispose();
        throw StateError('no saved session');
      }
      // Setting the connection and reading the backend goes through the
      // same providers the UI uses, so the "only backend_providers.dart
      // names a concrete adapter" rule holds in the background isolate too.
      container.read(activeConnectionProvider.notifier).state = connection;
      final backend = container.read(activeBackendProvider);
      if (backend == null) {
        container.dispose();
        throw StateError('no backend for the saved session');
      }
      // The container only exists to resolve the adapter; the catalog keeps
      // just the backend, so the container can go immediately.
      final catalog = BackendChapterCatalog(backend);
      container.dispose();
      return catalog;
    },
    marks: PrefsHighWaterMarkStore(),
    presenter: presenter,
  );
}
