import '../../../core/backend/models.dart';

/// Picks the page index a chapter should open on.
///
/// The server value is authoritative because it is the only source that
/// exists on web (no local database there) and it follows the user across
/// devices. The local row only fills in when the server has nothing, e.g.
/// after an offline session whose sync never landed. A chapter marked read
/// restarts from the top, since re-opening a finished chapter should read it
/// again rather than strand the user on its last page.
int resumePageFor({
  required int pageCount,
  bool serverRead = false,
  double? serverLastPage,
  bool localRead = false,
  double? localLastPage,
}) {
  if (pageCount <= 0 || serverRead) return 0;
  var page = serverLastPage ?? 0;
  // A local "read" row stores the final page; resuming there is the same
  // stranding problem as above, so only in-progress rows count.
  if (!localRead && localLastPage != null && localLastPage > page) {
    page = localLastPage;
  }
  return page.round().clamp(0, pageCount - 1);
}

/// The chapters before and after a given chapter in reading order.
///
/// Servers return chapters in arbitrary order, so adjacency is defined by
/// chapterNumber, not list position.
class AdjacentChapters {
  const AdjacentChapters({this.previous, this.next});

  final KsChapter? previous;
  final KsChapter? next;
}

AdjacentChapters adjacentChapters(List<KsChapter> chapters, String currentId) {
  final sorted = sortedByNumber(chapters);
  final index = sorted.indexWhere((c) => c.id == currentId);
  if (index == -1) return const AdjacentChapters();
  return AdjacentChapters(
    previous: index > 0 ? sorted[index - 1] : null,
    next: index + 1 < sorted.length ? sorted[index + 1] : null,
  );
}

List<KsChapter> sortedByNumber(List<KsChapter> chapters) =>
    [...chapters]..sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
