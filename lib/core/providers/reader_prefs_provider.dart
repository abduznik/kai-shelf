import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderMode { paged, webtoon }

const _readerModeKey = 'reader.mode';

class ReaderModeNotifier extends Notifier<ReaderMode> {
  @override
  ReaderMode build() {
    _load();
    return ReaderMode.paged;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_readerModeKey);
    if (stored == ReaderMode.webtoon.name) {
      state = ReaderMode.webtoon;
    }
  }

  Future<void> setMode(ReaderMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_readerModeKey, mode.name);
  }
}

final readerModeProvider = NotifierProvider<ReaderModeNotifier, ReaderMode>(
  ReaderModeNotifier.new,
);
