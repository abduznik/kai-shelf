import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChapterSortOrder { descending, ascending }

const _chapterSortKey = 'chapters.sortOrder';

class ChapterSortNotifier extends Notifier<ChapterSortOrder> {
  @override
  ChapterSortOrder build() {
    _load();
    return ChapterSortOrder.descending;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_chapterSortKey);
    if (stored == ChapterSortOrder.ascending.name) {
      state = ChapterSortOrder.ascending;
    }
  }

  Future<void> toggle() async {
    state = state == ChapterSortOrder.descending
        ? ChapterSortOrder.ascending
        : ChapterSortOrder.descending;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chapterSortKey, state.name);
  }
}

final chapterSortProvider =
    NotifierProvider<ChapterSortNotifier, ChapterSortOrder>(
  ChapterSortNotifier.new,
);
