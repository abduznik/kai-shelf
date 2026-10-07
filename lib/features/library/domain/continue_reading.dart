import '../../../core/backend/models.dart';
import '../../reader/domain/reading_flow.dart';

enum ContinueKind { start, resume, next, readAgain }

class ContinueTarget {
  const ContinueTarget(this.chapter, this.kind);

  final KsChapter chapter;
  final ContinueKind kind;

  String get label => switch (kind) {
        ContinueKind.start => 'Start reading',
        ContinueKind.readAgain => 'Read again',
        ContinueKind.resume ||
        ContinueKind.next =>
          'Continue chapter ${formatChapterNumber(chapter.chapterNumber)}',
      };
}

/// "12" for whole numbers, "12.5" for fractional ones.
String formatChapterNumber(double n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();

/// Decides where the detail screen's primary button should lead.
///
/// A half-read chapter wins over the next unread one, because that is where
/// the user actually stopped; the furthest such chapter is used if several
/// exist (e.g. after skipping around).
ContinueTarget? continueTarget(List<KsChapter> chapters) {
  if (chapters.isEmpty) return null;
  final sorted = sortedByNumber(chapters);

  final inProgress =
      sorted.where((c) => !c.read && (c.lastPageRead ?? 0) > 0).toList();
  if (inProgress.isNotEmpty) {
    return ContinueTarget(inProgress.last, ContinueKind.resume);
  }

  final firstUnread = sorted.where((c) => !c.read).toList();
  if (firstUnread.isEmpty) {
    return ContinueTarget(sorted.first, ContinueKind.readAgain);
  }
  final anyRead = sorted.any((c) => c.read);
  return ContinueTarget(
    firstUnread.first,
    anyRead ? ContinueKind.next : ContinueKind.start,
  );
}
