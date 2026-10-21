import 'package:workmanager/workmanager.dart';

import 'background_check.dart';
import 'notification_controller.dart';

/// Periodic background scheduling through Android's WorkManager (via
/// workmanager). Inexact by design: the OS batches the task around the
/// requested frequency, which is exactly what avoids the silent no-op that
/// exact repeating alarms hit on Android 12+ (Doze / alarm quota), and what
/// keeps the check off the battery-critical path.
class WorkmanagerCheckScheduler implements CheckScheduler {
  WorkmanagerCheckScheduler();

  /// Initialising WorkManager is idempotent but not free; keep it to one
  /// call per isolate (the foreground app's, in practice).
  static Future<void>? _initialised;

  Future<void> _ensureInitialised() =>
      _initialised ??= Workmanager().initialize(notificationCallbackDispatcher);

  @override
  Future<void> schedulePeriodic(Duration interval) async {
    await _ensureInitialised();
    await Workmanager().registerPeriodicTask(
      newChapterCheckUniqueName,
      newChapterCheckTaskName,
      frequency: interval,
      // update replaces the spec when one already exists (so an interval
      // change takes effect) and creates it otherwise, while keeping the
      // schedule stable across app launches.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 10),
    );
  }

  @override
  Future<void> cancel() async {
    await _ensureInitialised();
    // This app schedules exactly one periodic task, so cancelling all of
    // them is cancelling this one.
    await Workmanager().cancelAll();
  }
}
