import 'dart:async';

/// Debounces page-change events into periodic local saves plus a
/// best-effort server sync, so scrubbing through pages quickly doesn't
/// spam either the database or the network.
///
/// Takes plain callbacks rather than concrete repository/backend types so
/// it can be unit tested without a real database or network client.
class ReaderProgressTracker {
  ReaderProgressTracker({
    required this.totalPages,
    required this.onSaveLocal,
    this.onSyncServer,
    this.debounceDuration = const Duration(milliseconds: 600),
  });

  final int totalPages;
  final Future<void> Function(
      {required bool read, required double lastPageRead}) onSaveLocal;
  final Future<void> Function(
      {required bool read, required double lastPageRead})? onSyncServer;
  final Duration debounceDuration;

  Timer? _debounce;

  void onPageChanged(int pageIndex) {
    _debounce?.cancel();
    _debounce = Timer(debounceDuration, () => _persist(pageIndex));
  }

  Future<void> _persist(int pageIndex) async {
    final isLastPage = totalPages > 0 && pageIndex >= totalPages - 1;
    await onSaveLocal(read: isLastPage, lastPageRead: pageIndex.toDouble());

    if (onSyncServer == null) return;
    try {
      await onSyncServer!(read: isLastPage, lastPageRead: pageIndex.toDouble());
    } catch (_) {
      // Best-effort: local progress is already saved; server sync can
      // retry next time this chapter is opened while online.
    }
  }

  void dispose() {
    _debounce?.cancel();
  }
}
