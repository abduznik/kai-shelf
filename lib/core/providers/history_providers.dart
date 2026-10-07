import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/history/data/history_hidden_store.dart';
import '../../features/history/domain/history_logic.dart';
import '../backend/models.dart';
import '../backend/server_backend.dart';
import 'backend_providers.dart';

/// How many recent chapters the history screen loads.
const historyFetchLimit = 200;

final historyHiddenStoreProvider =
    Provider<HistoryHiddenStore>((ref) => HistoryHiddenStore());

/// Recently read chapters for the active server, minus whatever the user
/// removed. Auto-disposed so reopening the History tab fetches fresh data.
final historyProvider =
    AsyncNotifierProvider.autoDispose<HistoryNotifier, List<KsHistoryEntry>>(
        HistoryNotifier.new);

class HistoryNotifier extends AutoDisposeAsyncNotifier<List<KsHistoryEntry>> {
  HistoryHiddenState _hidden = const HistoryHiddenState();

  /// Entries as the server returned them, before hiding. Kept so "clear"
  /// knows what is currently on screen.
  List<KsHistoryEntry> _all = const [];

  String? get _serverId => ref.read(activeConnectionProvider)?.serverId;

  @override
  Future<List<KsHistoryEntry>> build() async {
    final backend = ref.watch(activeBackendProvider);
    final serverId = _serverId;
    if (backend is! HistoryCapableBackend || serverId == null) return const [];

    _hidden = await ref.read(historyHiddenStoreProvider).load(serverId);
    _all = await (backend as HistoryCapableBackend)
        .getHistory(limit: historyFetchLimit);
    return _hidden.visible(_all);
  }

  Future<void> remove(KsHistoryEntry entry) async {
    final serverId = _serverId;
    if (serverId == null) return;
    _hidden = _hidden.hide(entry);
    state = AsyncData(_hidden.visible(_all));
    await ref.read(historyHiddenStoreProvider).save(serverId, _hidden);
  }

  Future<void> clearAll() async {
    final serverId = _serverId;
    if (serverId == null) return;
    _hidden = _hidden.clear(_hidden.visible(_all));
    state = const AsyncData([]);
    await ref.read(historyHiddenStoreProvider).save(serverId, _hidden);
  }
}
