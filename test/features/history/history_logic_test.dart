import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/features/history/domain/history_logic.dart';

KsHistoryEntry entry(String id, DateTime at,
        {bool read = false, double? page, int? pages}) =>
    KsHistoryEntry(
      mangaId: 'm$id',
      mangaTitle: 'Manga $id',
      chapterId: id,
      chapterTitle: 'Chapter $id',
      lastReadAt: at,
      lastPageRead: page,
      pageCount: pages,
      read: read,
    );

void main() {
  final now = DateTime(2026, 10, 7, 12);

  group('groupHistoryByDay', () {
    test('buckets by local day, newest first, and sorts unsorted input', () {
      final days = groupHistoryByDay([
        entry('old', DateTime(2026, 10, 5, 9)),
        entry('a', DateTime(2026, 10, 7, 8)),
        entry('b', DateTime(2026, 10, 7, 11)),
        entry('y', DateTime(2026, 10, 6, 23, 59)),
      ]);
      expect(days.map((d) => d.day), [
        DateTime(2026, 10, 7),
        DateTime(2026, 10, 6),
        DateTime(2026, 10, 5),
      ]);
      expect(days[0].entries.map((e) => e.chapterId), ['b', 'a']);
      expect(days[1].entries.map((e) => e.chapterId), ['y']);
    });

    test('empty input gives no days', () {
      expect(groupHistoryByDay(const []), isEmpty);
    });
  });

  group('dayLabel', () {
    test('Today, Yesterday, then dates', () {
      expect(dayLabel(DateTime(2026, 10, 7, 1), now), 'Today');
      expect(dayLabel(DateTime(2026, 10, 6, 23), now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 10, 5), now), 'Mon, 5 Oct');
    });

    test('adds the year only when it differs', () {
      expect(dayLabel(DateTime(2025, 12, 31), now), 'Wed, 31 Dec 2025');
    });

    test('Yesterday works across a month boundary', () {
      expect(dayLabel(DateTime(2026, 9, 30), DateTime(2026, 10, 1, 8)),
          'Yesterday');
    });
  });

  group('progressLabel', () {
    test('finished wins over page numbers', () {
      expect(progressLabel(entry('a', now, read: true, page: 3, pages: 4)),
          'Finished');
    });

    test('zero-based page index shows as a one-based page of total', () {
      expect(
          progressLabel(entry('a', now, page: 6, pages: 24)), 'Page 7 of 24');
    });

    test('clamps to the total and copes with an unknown total', () {
      expect(
          progressLabel(entry('a', now, page: 30, pages: 24)), 'Page 24 of 24');
      expect(progressLabel(entry('a', now, page: 6)), 'Page 7');
    });

    test('no page recorded reads as started', () {
      expect(progressLabel(entry('a', now)), 'Started');
    });
  });

  group('HistoryHiddenState', () {
    test('removed entry stays hidden until it is read again', () {
      final e = entry('a', DateTime(2026, 10, 7, 8));
      final state = const HistoryHiddenState().hide(e);
      expect(state.isHidden(e), isTrue);
      expect(state.isHidden(entry('a', DateTime(2026, 10, 7, 9))), isFalse);
      expect(state.isHidden(entry('b', DateTime(2026, 10, 7, 8))), isFalse);
    });

    test('clear hides what is shown but not later reads', () {
      final shown = [
        entry('a', DateTime(2026, 10, 7, 8)),
        entry('b', DateTime(2026, 10, 7, 9)),
      ];
      final state = const HistoryHiddenState().clear(shown);
      expect(state.visible(shown), isEmpty);
      expect(state.isHidden(entry('c', DateTime(2026, 10, 7, 10))), isFalse);
    });

    test('clear keeps per-chapter cutoffs newer than the shown entries', () {
      final hiddenNewer = entry('x', DateTime(2026, 10, 7, 10));
      final shown = [entry('a', DateTime(2026, 10, 7, 8))];
      final state = const HistoryHiddenState().hide(hiddenNewer).clear(shown);
      expect(state.isHidden(hiddenNewer), isTrue);
    });

    test('survives a JSON round trip with sub-millisecond timestamps', () {
      final e = entry('a', DateTime.utc(2026, 10, 7, 15, 17, 9, 807, 890));
      final restored = HistoryHiddenState.fromJson(
          const HistoryHiddenState().hide(e).toJson());
      expect(restored.isHidden(e), isTrue);
    });
  });
}
