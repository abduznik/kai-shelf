import '../backend/models.dart';

/// The server's chapters for one tracked title, as fetched during a check.
class TitleChapterSnapshot {
  const TitleChapterSnapshot({required this.title, required this.chapters});

  /// Manga title, used as the notification headline.
  final String title;
  final List<KsChapter> chapters;

  /// Highest chapter number the server reports, or null when the title has
  /// no chapters with a usable number (an empty list, or only NaN-numbered
  /// specials). Chapters numbered 0 are legitimate and count.
  double? get newestChapterNumber {
    double? newest;
    for (final chapter in chapters) {
      final number = chapter.chapterNumber;
      if (number.isNaN) continue;
      if (newest == null || number > newest) newest = number;
    }
    return newest;
  }

  /// The chapter backing [newestChapterNumber], for naming it in the
  /// notification body.
  KsChapter? get newestChapter {
    final newest = newestChapterNumber;
    if (newest == null) return null;
    KsChapter? best;
    for (final chapter in chapters) {
      if (chapter.chapterNumber == newest) best = chapter;
    }
    return best;
  }
}

/// One notification's worth of content: everything the presenter needs to
/// display it and deep-link back to the title.
class NewChapterNotification {
  const NewChapterNotification({
    required this.mangaId,
    required this.title,
    required this.newChapterCount,
    required this.latestChapterNumber,
    this.latestChapterTitle,
  });

  final String mangaId;
  final String title;

  /// How many chapters are newer than the stored high-water mark.
  final int newChapterCount;
  final double latestChapterNumber;
  final String? latestChapterTitle;

  /// App route a tapped notification opens.
  String get route => '/manga/$mangaId';

  /// Chapter numbers arrive as doubles from every backend; only show the
  /// fraction when there is one ("Chapter 12 is out", "Chapter 12.5 is out").
  String get latestChapterLabel =>
      latestChapterNumber == latestChapterNumber.roundToDouble()
          ? latestChapterNumber.toInt().toString()
          : latestChapterNumber.toString();

  String get body => newChapterCount == 1
      ? 'Chapter $latestChapterLabel is out'
      : '$newChapterCount new chapters out';
}

/// What one check decided: which notifications to show and which high-water
/// marks to persist (the full merged map, since the store keeps one blob).
class ChapterCheckOutcome {
  const ChapterCheckOutcome({required this.notifications, required this.marks});

  final List<NewChapterNotification> notifications;
  final Map<String, double> marks;
}

/// Pure decision logic for one check — the piece that must never notify
/// twice about chapters that already exist, so it is unit-tested without any
/// storage, network or platform involvement.
///
/// A title the store has never seen is *baselined*: its current newest
/// chapter becomes the mark and nothing is reported. That is what keeps the
/// first check (or a freshly added title) from flooding the user with every
/// chapter published so far.
ChapterCheckOutcome detectNewChapters({
  required Map<String, double> knownMarks,
  required Map<String, TitleChapterSnapshot> snapshots,
}) {
  final notifications = <NewChapterNotification>[];
  final marks = Map<String, double>.of(knownMarks);

  for (final mangaId in snapshots.keys.toList()..sort()) {
    final snapshot = snapshots[mangaId]!;
    final newest = snapshot.newestChapterNumber;
    if (newest == null) continue;

    final known = knownMarks[mangaId];
    if (known == null) {
      marks[mangaId] = newest;
      continue;
    }
    if (newest <= known) continue;

    final newCount = snapshot.chapters
        .where((c) => !c.chapterNumber.isNaN && c.chapterNumber > known)
        .length;
    marks[mangaId] = newest;
    notifications.add(NewChapterNotification(
      mangaId: mangaId,
      title: snapshot.title,
      newChapterCount: newCount < 1 ? 1 : newCount,
      latestChapterNumber: newest,
      latestChapterTitle: snapshot.newestChapter?.title,
    ));
  }

  return ChapterCheckOutcome(notifications: notifications, marks: marks);
}

/// Where the engine gets its view of the server from. Kept behind an
/// interface so the engine runs under `dart test` with in-memory fakes while
/// production feeds it the active [ServerBackend] adapter.
abstract class ChapterCatalog {
  /// Every title worth tracking (the in-library manga).
  Future<List<KsManga>> trackedManga();

  /// All chapters of one title, as the server reports them.
  Future<List<KsChapter>> chaptersFor(String mangaId);
}

/// Per-title high-water marks: manga id → newest chapter number seen.
abstract class HighWaterMarkStore {
  Future<Map<String, double>> load();
  Future<void> save(Map<String, double> marks);
}

/// Displays new-chapter notifications. Behind an interface because platform
/// channels don't exist under `flutter test`.
abstract class NotificationPresenter {
  Future<void> show(NewChapterNotification notification);
}

/// One background check: fetch the newest chapter per tracked title, compare
/// against the stored marks, persist the new marks and show one notification
/// per title that gained chapters.
class ChapterCheckEngine {
  const ChapterCheckEngine({
    required this.catalog,
    required this.marks,
    required this.presenter,
  });

  final ChapterCatalog catalog;
  final HighWaterMarkStore marks;
  final NotificationPresenter presenter;

  /// Returns the notifications that were shown (empty on a quiet check).
  Future<List<NewChapterNotification>> run() async {
    final known = await marks.load();

    final snapshots = <String, TitleChapterSnapshot>{};
    for (final manga in await catalog.trackedManga()) {
      if (!manga.inLibrary) continue;
      try {
        snapshots[manga.id] = TitleChapterSnapshot(
          title: manga.title,
          chapters: await catalog.chaptersFor(manga.id),
        );
      } catch (_) {
        // One unreachable title must not sink the run; its old mark stays
        // untouched, so the next successful check still compares correctly.
      }
    }

    final outcome = detectNewChapters(knownMarks: known, snapshots: snapshots);
    if (!_sameMarks(known, outcome.marks)) {
      await marks.save(outcome.marks);
    }
    for (final notification in outcome.notifications) {
      await presenter.show(notification);
    }
    return outcome.notifications;
  }

  static bool _sameMarks(Map<String, double> a, Map<String, double> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
