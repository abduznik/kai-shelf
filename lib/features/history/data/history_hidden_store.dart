import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/history_logic.dart';

/// Persists which history entries the user removed, per server. Lives in
/// shared_preferences rather than sqlite so it also works on web, where the
/// local database does not exist.
class HistoryHiddenStore {
  String _key(String serverId) => 'history.hidden.$serverId';

  Future<HistoryHiddenState> load(String serverId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(serverId));
      if (raw == null) return const HistoryHiddenState();
      return HistoryHiddenState.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const HistoryHiddenState();
    }
  }

  Future<void> save(String serverId, HistoryHiddenState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(serverId), jsonEncode(state.toJson()));
  }
}
