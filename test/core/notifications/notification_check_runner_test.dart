import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/notifications/notification_check_runner.dart';

import 'notification_test_support.dart';

void main() {
  group('runChapterCheck', () {
    test('a disabled feature performs no checks at all', () async {
      final catalog = FakeChapterCatalog(manga: [manga('m1')]);
      final marks = FakeHighWaterMarkStore({'m1': 1.0});
      final presenter = FakePresenter();

      final outcome = await runChapterCheck(
        enabled: () async => false,
        incognito: () async => false,
        // Would throw if it were ever called: no checks at all means the
        // catalog is never even constructed, let alone queried.
        catalog: () => throw StateError('catalog must not be built'),
        marks: marks,
        presenter: presenter,
      );

      expect(outcome.status, NotificationCheckStatus.disabled);
      expect(catalog.trackedMangaCalls, 0);
      expect(presenter.shown, isEmpty);
      expect(marks.marks, {'m1': 1.0});
    });

    test('incognito suppresses the check entirely', () async {
      final catalog = FakeChapterCatalog(manga: [manga('m1')]);
      final presenter = FakePresenter();

      final outcome = await runChapterCheck(
        enabled: () async => true,
        incognito: () async => true,
        catalog: () => throw StateError('catalog must not be built'),
        marks: FakeHighWaterMarkStore({'m1': 1.0}),
        presenter: presenter,
      );

      expect(outcome.status, NotificationCheckStatus.incognito);
      expect(catalog.trackedMangaCalls, 0);
      expect(presenter.shown, isEmpty);
    });

    test('an enabled check runs the engine and reports its notifications',
        () async {
      final catalog = FakeChapterCatalog(
        manga: [manga('m1', title: 'Manga One')],
        chaptersByManga: {
          'm1': [chapter('m1', 1), chapter('m1', 2)],
        },
      );
      final marks = FakeHighWaterMarkStore({'m1': 1.0});
      final presenter = FakePresenter();

      final outcome = await runChapterCheck(
        enabled: () async => true,
        incognito: () async => false,
        catalog: () async => catalog,
        marks: marks,
        presenter: presenter,
      );

      expect(outcome.status, NotificationCheckStatus.completed);
      expect(outcome.notifications.single.mangaId, 'm1');
      expect(presenter.shown.single.route, '/manga/m1');
      expect(marks.marks, {'m1': 2.0});
    });

    test('no connection is reported instead of crashing', () async {
      final outcome = await runChapterCheck(
        enabled: () async => true,
        incognito: () async => false,
        catalog: () async => throw StateError('no server session'),
        marks: FakeHighWaterMarkStore(),
        presenter: FakePresenter(),
      );

      expect(outcome.status, NotificationCheckStatus.noConnection);
    });
  });
}
