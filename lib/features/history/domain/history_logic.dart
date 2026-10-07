import '../../../core/backend/models.dart';

/// History entries that fall on one calendar day, newest first.
class HistoryDay {
  const HistoryDay({required this.day, required this.entries});

  /// Midnight of the day, in local time.
  final DateTime day;
  final List<KsHistoryEntry> entries;
}

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Buckets [entries] by local calendar day, newest day first and newest
/// entry first within a day. Sorts itself so callers don't have to trust
/// the server's ordering (Kavita's is assembled client-side).
List<HistoryDay> groupHistoryByDay(List<KsHistoryEntry> entries) {
  final sorted = [...entries]
    ..sort((a, b) => b.lastReadAt.compareTo(a.lastReadAt));
  final days = <HistoryDay>[];
  for (final entry in sorted) {
    final day = _dayOf(entry.lastReadAt);
    if (days.isNotEmpty && days.last.day == day) {
      days.last.entries.add(entry);
    } else {
      days.add(HistoryDay(day: day, entries: [entry]));
    }
  }
  return days;
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Today", "Yesterday", or e.g. "Mon, 5 Oct" (with the year once it is not
/// the current one).
String dayLabel(DateTime day, DateTime now) {
  final today = _dayOf(now);
  final target = _dayOf(day);
  // Calendar-day difference via DateTime(y, m, d - 1), not Duration, so
  // daylight-saving shifts can't turn "yesterday" into "2 days ago".
  if (target == today) return 'Today';
  if (target == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  final base =
      '${_weekdays[target.weekday - 1]}, ${target.day} ${_months[target.month - 1]}';
  return target.year == today.year ? base : '$base ${target.year}';
}

/// How far into the chapter the reader got: "Finished", "Page 7 of 24",
/// "Page 7" when the total is unknown, or "Started" with no page recorded.
String progressLabel(KsHistoryEntry entry) {
  if (entry.read) return 'Finished';
  final last = entry.lastPageRead;
  if (last == null) return 'Started';
  var page = last.round() + 1;
  final total = entry.pageCount;
  if (total != null && total > 0) {
    if (page > total) page = total;
    return 'Page $page of $total';
  }
  return 'Page $page';
}

/// Which entries the user removed from history on this device.
///
/// None of the three servers lets a client erase a chapter's last-read
/// time (Suwayomi's chapter patch has no lastReadAt field, Komga and Kavita
/// expose no per-chapter "forget"), and un-reading a chapter would destroy
/// real progress. So removal is local: an entry is hidden while its
/// lastReadAt is not newer than the moment it was removed, and reappears
/// if the chapter is read again afterwards.
class HistoryHiddenState {
  const HistoryHiddenState({this.clearedAt, this.chapters = const {}});

  /// Everything last read at or before this moment is hidden.
  final DateTime? clearedAt;

  /// Per-chapter cutoff: hidden while lastReadAt is at or before it.
  final Map<String, DateTime> chapters;

  bool isHidden(KsHistoryEntry entry) {
    final cleared = clearedAt;
    if (cleared != null && !entry.lastReadAt.isAfter(cleared)) return true;
    final cutoff = chapters[entry.chapterId];
    return cutoff != null && !entry.lastReadAt.isAfter(cutoff);
  }

  List<KsHistoryEntry> visible(List<KsHistoryEntry> entries) =>
      entries.where((e) => !isHidden(e)).toList();

  HistoryHiddenState hide(KsHistoryEntry entry) => HistoryHiddenState(
        clearedAt: clearedAt,
        chapters: {...chapters, entry.chapterId: entry.lastReadAt},
      );

  /// Hides everything currently in [entries]. The cutoff is the newest
  /// shown entry rather than "now", so a chapter read a moment later (or
  /// on another device) still shows up. Per-chapter cutoffs are kept: one
  /// may be newer than anything still shown.
  HistoryHiddenState clear(List<KsHistoryEntry> entries) {
    if (entries.isEmpty) return this;
    final newest =
        entries.map((e) => e.lastReadAt).reduce((a, b) => a.isAfter(b) ? a : b);
    return HistoryHiddenState(clearedAt: newest, chapters: chapters);
  }

  Map<String, dynamic> toJson() => {
        // Microseconds: Kavita timestamps are sub-millisecond, and rounding
        // down would leave an entry fractionally newer than its own cutoff.
        'clearedAt': clearedAt?.microsecondsSinceEpoch,
        'chapters': {
          for (final e in chapters.entries)
            e.key: e.value.microsecondsSinceEpoch,
        },
      };

  factory HistoryHiddenState.fromJson(Map<String, dynamic> json) {
    final cleared = json['clearedAt'] as int?;
    return HistoryHiddenState(
      clearedAt:
          cleared == null ? null : DateTime.fromMicrosecondsSinceEpoch(cleared),
      chapters: {
        for (final e in (json['chapters'] as Map? ?? {}).entries)
          e.key as String: DateTime.fromMicrosecondsSinceEpoch(e.value as int),
      },
    );
  }
}
