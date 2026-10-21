import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/notifications/chapter_check_engine.dart';
import 'package:kai_shelf/core/notifications/notification_controller.dart';
import 'package:kai_shelf/core/notifications/notification_settings.dart';

/// In-memory [ChapterCatalog] that records every touch, so tests can assert
/// that a suppressed check never reached the server.
class FakeChapterCatalog implements ChapterCatalog {
  FakeChapterCatalog({this.manga = const [], this.chaptersByManga = const {}});

  final List<KsManga> manga;
  final Map<String, List<KsChapter>> chaptersByManga;

  int trackedMangaCalls = 0;

  @override
  Future<List<KsManga>> trackedManga() async {
    trackedMangaCalls++;
    return manga;
  }

  @override
  Future<List<KsChapter>> chaptersFor(String mangaId) async =>
      chaptersByManga[mangaId] ?? const [];
}

class FakeHighWaterMarkStore implements HighWaterMarkStore {
  FakeHighWaterMarkStore([Map<String, double>? initial])
      : marks = {...?initial};

  Map<String, double> marks;

  @override
  Future<Map<String, double>> load() async => {...marks};

  @override
  Future<void> save(Map<String, double> newMarks) async {
    marks = {...newMarks};
  }
}

class FakePresenter implements NotificationPresenter {
  final List<NewChapterNotification> shown = [];

  @override
  Future<void> show(NewChapterNotification notification) async {
    shown.add(notification);
  }
}

/// Toggle/interval state with no persistence, for controller tests.
class FakeSettingsStore implements NotificationSettingsStore {
  FakeSettingsStore({
    bool enabled = false,
    NotificationCheckInterval interval = NotificationCheckInterval.hourly,
  })  : _enabled = enabled,
        _interval = interval;

  bool _enabled;
  NotificationCheckInterval _interval;

  @override
  Future<bool> isEnabled() async => _enabled;

  @override
  Future<NotificationCheckInterval> interval() async => _interval;

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
  }

  @override
  Future<void> setInterval(NotificationCheckInterval interval) async {
    _interval = interval;
  }
}

class FakeScheduler implements CheckScheduler {
  final List<Duration> scheduled = [];
  int cancelCalls = 0;
  bool throwOnSchedule = false;

  @override
  Future<void> schedulePeriodic(Duration interval) async {
    if (throwOnSchedule) {
      throw StateError('workmanager unavailable');
    }
    scheduled.add(interval);
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}

class FakePermissionGate implements NotificationPermissionGate {
  FakePermissionGate({this.granted = true});

  bool? granted;
  int requestCalls = 0;
  bool throwOnRequest = false;

  @override
  Future<bool?> requestPermission() async {
    requestCalls++;
    if (throwOnRequest) {
      throw StateError('notification plugin unavailable');
    }
    return granted;
  }
}

KsManga manga(String id, {String? title, bool inLibrary = true}) =>
    KsManga(id: id, title: title ?? 'Title $id', inLibrary: inLibrary);

KsChapter chapter(String mangaId, double number) => KsChapter(
      id: '$mangaId-c$number',
      mangaId: mangaId,
      title: 'Chapter $number',
      chapterNumber: number,
    );
