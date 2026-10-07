import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _feedSourcesKey = 'feed.sourceIds';

/// Which sources the Feed shows. Null means the user never chose, so the
/// screen falls back to a small default instead of firing a request at every
/// installed source.
class FeedSourcesNotifier extends AsyncNotifier<Set<String>?> {
  @override
  Future<Set<String>?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_feedSourcesKey)?.toSet();
  }

  Future<void> set(Set<String> ids) async {
    state = AsyncData(ids);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_feedSourcesKey, ids.toList()..sort());
  }
}

final feedSourcesProvider =
    AsyncNotifierProvider<FeedSourcesNotifier, Set<String>?>(
        FeedSourcesNotifier.new);
