import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/features/library/domain/continue_reading.dart';
import 'package:kai_shelf/features/reader/domain/reading_flow.dart';

KsChapter ch(String id, double n, {bool read = false, double? page}) =>
    KsChapter(
      id: id,
      mangaId: 'm',
      title: 'Chapter $n',
      chapterNumber: n,
      read: read,
      lastPageRead: page,
    );

void main() {
  group('resumePageFor', () {
    test('starts at the top without progress', () {
      expect(resumePageFor(pageCount: 20), 0);
    });

    test('uses server progress', () {
      expect(resumePageFor(pageCount: 20, serverLastPage: 7), 7);
    });

    test('restarts a chapter already marked read', () {
      expect(resumePageFor(pageCount: 20, serverRead: true, serverLastPage: 19),
          0);
    });

    test('clamps to the valid range', () {
      expect(resumePageFor(pageCount: 5, serverLastPage: 40), 4);
      expect(resumePageFor(pageCount: 5, serverLastPage: -3), 0);
      expect(resumePageFor(pageCount: 0, serverLastPage: 3), 0);
    });

    test('falls back to newer local progress when the server has none', () {
      expect(resumePageFor(pageCount: 20, localLastPage: 9), 9);
      expect(
          resumePageFor(pageCount: 20, serverLastPage: 3, localLastPage: 9), 9);
      expect(resumePageFor(pageCount: 20, serverLastPage: 12, localLastPage: 9),
          12);
    });

    test('ignores a local row that recorded the chapter as finished', () {
      expect(
          resumePageFor(pageCount: 20, localRead: true, localLastPage: 19), 0);
    });
  });

  group('adjacentChapters', () {
    final chapters = [ch('c3', 3), ch('c1', 1), ch('c2', 2)];

    test('orders by chapter number, not list position', () {
      final a = adjacentChapters(chapters, 'c2');
      expect(a.previous!.id, 'c1');
      expect(a.next!.id, 'c3');
    });

    test('has no previous at the start and no next at the end', () {
      expect(adjacentChapters(chapters, 'c1').previous, isNull);
      expect(adjacentChapters(chapters, 'c3').next, isNull);
    });

    test('handles unknown ids and fractional numbers', () {
      expect(adjacentChapters(chapters, 'zzz').next, isNull);
      final withHalf = [ch('a', 1), ch('b', 2), ch('h', 1.5)];
      expect(adjacentChapters(withHalf, 'a').next!.id, 'h');
    });
  });

  group('continueTarget', () {
    test('no chapters means no button', () {
      expect(continueTarget([]), isNull);
    });

    test('nothing read starts at the first chapter', () {
      final t = continueTarget([ch('b', 2), ch('a', 1)])!;
      expect(t.chapter.id, 'a');
      expect(t.kind, ContinueKind.start);
      expect(t.label, 'Start reading');
    });

    test('continues at the first unread chapter', () {
      final t = continueTarget(
          [ch('a', 1, read: true), ch('c', 3), ch('b', 2, read: true)])!;
      expect(t.chapter.id, 'c');
      expect(t.label, 'Continue chapter 3');
    });

    test('resumes a chapter in progress ahead of unread ones', () {
      final t = continueTarget(
          [ch('a', 1, read: true), ch('b', 2, page: 4), ch('c', 3)])!;
      expect(t.chapter.id, 'b');
      expect(t.kind, ContinueKind.resume);
      expect(t.label, 'Continue chapter 2');
    });

    test('formats fractional chapter numbers', () {
      final t = continueTarget([ch('a', 1, read: true), ch('h', 1.5)])!;
      expect(t.label, 'Continue chapter 1.5');
    });

    test('offers to read again when everything is read', () {
      final t = continueTarget(
          [ch('b', 2, read: true), ch('a', 1, read: true, page: 9)])!;
      expect(t.chapter.id, 'a');
      expect(t.label, 'Read again');
    });
  });
}
