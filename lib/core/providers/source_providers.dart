import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/models.dart';
import '../backend/server_backend.dart';
import 'backend_providers.dart';

/// Lists installed sources for backends that support catalog discovery.
/// Returns an empty list for backends without [SourceCapableBackend]
/// (Komga/Kavita), rather than throwing — callers can just hide the
/// discover entry point when this comes back empty.
final sourceListProvider = FutureProvider.autoDispose<List<KsSource>>((ref) async {
  final backend = ref.watch(activeBackendProvider);
  if (backend is! SourceCapableBackend) return [];
  return (backend as SourceCapableBackend).getSources();
});

class SourceSearchParams {
  const SourceSearchParams({required this.sourceId, required this.query});

  final String sourceId;
  final String query;

  @override
  bool operator ==(Object other) =>
      other is SourceSearchParams &&
      other.sourceId == sourceId &&
      other.query == query;

  @override
  int get hashCode => Object.hash(sourceId, query);
}

final sourceSearchProvider = FutureProvider.autoDispose
    .family<List<KsSourceManga>, SourceSearchParams>((ref, params) async {
  if (params.query.isEmpty) return [];
  final backend = ref.watch(activeBackendProvider);
  if (backend is! SourceCapableBackend) return [];
  return (backend as SourceCapableBackend)
      .searchSource(params.sourceId, params.query);
});
