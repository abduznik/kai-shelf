import 'chapter_check_engine.dart';

/// How one background check ended, for logging and tests.
enum NotificationCheckStatus {
  /// The feature is switched off: nothing was fetched, nothing scheduled.
  disabled,

  /// Incognito is on: no checks, no notifications (issue #9 design note).
  incognito,

  /// No saved session, or the server could not be reached this time.
  noConnection,

  completed,
}

class NotificationCheckOutcome {
  const NotificationCheckOutcome(this.status, [this.notifications = const []]);

  final NotificationCheckStatus status;
  final List<NewChapterNotification> notifications;
}

/// Runs one chapter check with everything injected, in the exact order that
/// makes the acceptance criteria testable:
///
///  1. disabled → return before the catalog is even built, so "toggle off =
///     no checks performed at all" is a hard guarantee, not a hope;
///  2. incognito → same, so private reading sessions stay invisible;
///  3. otherwise run [ChapterCheckEngine] over the real catalog.
///
/// The workmanager background task and the foreground "check now" path both
/// funnel through this one function.
Future<NotificationCheckOutcome> runChapterCheck({
  required Future<bool> Function() enabled,
  required Future<bool> Function() incognito,
  required Future<ChapterCatalog> Function() catalog,
  required HighWaterMarkStore marks,
  required NotificationPresenter presenter,
}) async {
  if (!await enabled()) {
    return const NotificationCheckOutcome(NotificationCheckStatus.disabled);
  }
  if (await incognito()) {
    return const NotificationCheckOutcome(NotificationCheckStatus.incognito);
  }

  try {
    final engine = ChapterCheckEngine(
      catalog: await catalog(),
      marks: marks,
      presenter: presenter,
    );
    final notifications = await engine.run();
    return NotificationCheckOutcome(
        NotificationCheckStatus.completed, notifications);
  } catch (_) {
    // No session, unreachable server, unreadable credentials — all of which
    // mean "nothing to report this time". The marks are untouched, so the
    // next successful check picks up exactly where this one would have.
    return const NotificationCheckOutcome(NotificationCheckStatus.noConnection);
  }
}
