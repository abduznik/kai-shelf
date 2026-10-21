import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/notifications/chapter_check_engine.dart';

class _FakeCatalog implements ChapterCatalog {
  _FakeCatalog({this.manga = const [], this.chaptersByManga = const {}});

  final List<KsManga> manga;
  final Map<String, List<KsChapter>> chaptersByManga;

  /// Ids whose chapter fetch throws, to prove one bad title can't sink a run.
  final Set<String> failingIds = {};

  final List<String> fetchedIds = [];

  @override
  Future<List<KsManga>> trackedManga() async => manga;

  @override
  Future<List<KsChapter>> chaptersFor(String mangaId) async {
    fetchedIds.add(mangaId);
    if (failingIds.contains(mangaId)) {
      throw StateError('server unreachable');
    }
    return chaptersByManga[mangaId] ?? const [];
  }
}

class _MemoryMarks implements HighWaterMarkStore {
  _MemoryMarks([Map<String, double>? initial]) : marks = {...?initial};

  Map<String, double> marks;
  int saveCalls = 0;

  @override
  Future<Map<String, double>> load() async => {...marks};

  @override
  Future<void> save(Map<String, double> newMarks) async {
    saveCalls++;
    marks = {...newMarks};
  }
}

class _RecordingPresenter implements NotificationPresenter {
  final List<NewChapterNotification> shown = [];

  @override
  Future<void> show(NewChapterNotification notification) async {
    shown.add(notification);
  }
}

KsManga _manga(String id, {String? title, bool inLibrary = true}) =>
    KsManga(id: id, title: title ?? 'Title $id', inLibrary: inLibrary);

KsChapter _chapter(String mangaId, double number, {String? title}) => KsChapter(
      id: '$mangaId-c$number',
      mangaId: mangaId,
      title: title ?? 'Chapter $number',
      chapterNumber: number,
    );

void main() {
  group('detectNewChapters', () {
    test('first sighting of a title seeds the mark without notifying', () {
      final outcome = detectNewChapters(
        knownMarks: const {},
        snapshots: {
          'm1': TitleChapterSnapshot(
            title: 'Manga One',
            chapters: [_chapter('m1', 1), _chapter('m1', 2)],
          ),
        },
      );

      expect(outcome.notifications, isEmpty);
      expect(outcome.marks, {'m1': 2.0});
    });

    test('a chapter newer than the mark notifies with count and route', () {
      final outcome = detectNewChapters(
        knownMarks: const {'m1': 3.0},
        snapshots: {
          'm1': TitleChapterSnapshot(
            title: 'Manga One',
            chapters: [
              _chapter('m1', 3),
              _chapter('m1', 4),
              _chapter('m1', 4.5),
            ],
          ),
        },
      );

      expect(outcome.notifications, hasLength(1));
      final notification = outcome.notifications.single;
      expect(notification.mangaId, 'm1');
      expect(notification.title, 'Manga One');
      expect(notification.newChapterCount, 2);
      expect(notification.latestChapterNumber, 4.5);
      expect(notification.route, '/manga/m1');
      expect(outcome.marks, {'m1': 4.5});
    });

    test('an unchanged title never notifies twice', () {
      final snapshots = {
        'm1': TitleChapterSnapshot(
          title: 'Manga One',
          chapters: [_chapter('m1', 1), _chapter('m1', 2)],
        ),
      };

      final first = detectNewChapters(
          knownMarks: const {'m1': 1.0}, snapshots: snapshots);
      expect(first.notifications, hasLength(1));

      final second =
          detectNewChapters(knownMarks: first.marks, snapshots: snapshots);
      expect(second.notifications, isEmpty);
      expect(second.marks, {'m1': 2.0});
    });

    test('only titles with new chapters notify', () {
      final outcome = detectNewChapters(
        knownMarks: const {'m1': 5.0, 'm2': 2.0, 'm3': 1.0},
        snapshots: {
          'm1': TitleChapterSnapshot(
            title: 'Caught up',
            chapters: [_chapter('m1', 5)],
          ),
          'm2': TitleChapterSnapshot(
            title: 'Behind',
            chapters: [_chapter('m2', 2), _chapter('m2', 3)],
          ),
          'm3': TitleChapterSnapshot(
            title: 'No chapters',
            chapters: const [],
          ),
        },
      );

      expect(outcome.notifications, hasLength(1));
      expect(outcome.notifications.single.mangaId, 'm2');
      expect(outcome.marks, {'m1': 5.0, 'm2': 3.0, 'm3': 1.0});
    });

    test('marks of titles absent from this run are kept', () {
      final outcome = detectNewChapters(
        knownMarks: const {'gone': 7.0},
        snapshots: {
          'm1': TitleChapterSnapshot(
            title: 'Manga One',
            chapters: [_chapter('m1', 1)],
          ),
        },
      );

      expect(outcome.marks, {'gone': 7.0, 'm1': 1.0});
    });
  });

  group('ChapterCheckEngine.run', () {
    test('shows one notification per changed title and persists marks',
        () async {
      final catalog = _FakeCatalog(
        manga: [
          _manga('m1', title: 'Manga One'),
          _manga('m2', title: 'Manga Two')
        ],
        chaptersByManga: {
          'm1': [_chapter('m1', 1), _chapter('m1', 2)],
          'm2': [_chapter('m2', 9)],
        },
      );
      final marks = _MemoryMarks({'m1': 1.0, 'm2': 9.0});
      final presenter = _RecordingPresenter();

      final engine = ChapterCheckEngine(
        catalog: catalog,
        marks: marks,
        presenter: presenter,
      );
      final notifications = await engine.run();

      expect(notifications.map((n) => n.mangaId), ['m1']);
      expect(presenter.shown.single.newChapterCount, 1);
      expect(marks.marks, {'m1': 2.0, 'm2': 9.0});
      expect(marks.saveCalls, 1);
    });

    test('a second run with nothing new notifies nobody', () async {
      final catalog = _FakeCatalog(
        manga: [_manga('m1')],
        chaptersByManga: {
          'm1': [_chapter('m1', 1), _chapter('m1', 2)],
        },
      );
      final marks = _MemoryMarks();
      final presenter = _RecordingPresenter();
      final engine = ChapterCheckEngine(
        catalog: catalog,
        marks: marks,
        presenter: presenter,
      );

      await engine.run(); // Baseline: seeds, no notification.
      final second = await engine.run();

      expect(second, isEmpty);
      expect(presenter.shown, isEmpty);
      expect(marks.marks, {'m1': 2.0});
    });

    test('a failing title fetch does not abort the run or lose its mark',
        () async {
      final catalog = _FakeCatalog(
        manga: [_manga('m1'), _manga('m2')],
        chaptersByManga: {
          'm1': [_chapter('m1', 1), _chapter('m1', 2)],
        },
      );
      catalog.failingIds.add('m2');
      final marks = _MemoryMarks({'m1': 1.0, 'm2': 4.0});
      final presenter = _RecordingPresenter();
      final engine = ChapterCheckEngine(
        catalog: catalog,
        marks: marks,
        presenter: presenter,
      );

      final notifications = await engine.run();

      expect(notifications.map((n) => n.mangaId), ['m1']);
      // The failing title keeps its old mark instead of being reset.
      expect(marks.marks, {'m1': 2.0, 'm2': 4.0});
    });

    test('titles outside the library are not checked', () async {
      final catalog = _FakeCatalog(
        manga: [_manga('m1', inLibrary: false)],
      );
      final marks = _MemoryMarks();
      final engine = ChapterCheckEngine(
        catalog: catalog,
        marks: marks,
        presenter: _RecordingPresenter(),
      );

      final notifications = await engine.run();

      expect(notifications, isEmpty);
      expect(catalog.fetchedIds, isEmpty);
      expect(marks.marks, isEmpty);
    });
  });

  group('notification wording', () {
    test('a single new chapter names the chapter number', () {
      final outcome = detectNewChapters(
        knownMarks: const {'m1': 1.0},
        snapshots: {
          'm1': TitleChapterSnapshot(
            title: 'Manga One',
            chapters: [_chapter('m1', 1), _chapter('m1', 2)],
          ),
        },
      );

      expect(outcome.notifications.single.body, 'Chapter 2 is out');
    });

    test('several new chapters are summarised as a count', () {
      final outcome = detectNewChapters(
        knownMarks: const {'m1': 1.0},
        snapshots: {
          'm1': TitleChapterSnapshot(
            title: 'Manga One',
            chapters: [
              _chapter('m1', 1),
              _chapter('m1', 2),
              _chapter('m1', 3),
              _chapter('m1', 4),
            ],
          ),
        },
      );

      expect(outcome.notifications.single.body, '3 new chapters out');
    });
  });
}
