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
    this.isIncognito,
    this.debounceDuration = const Duration(milliseconds: 600),
  });

  final int totalPages;
  final Future<void> Function(
      {required bool read, required double lastPageRead}) onSaveLocal;
  final Future<void> Function(
      {required bool read, required double lastPageRead})? onSyncServer;
  final Duration debounceDuration;

  /// Consulted at persist time, not just when the page changes, so turning
  /// incognito on while a save is already pending still suppresses it. When
  /// true nothing is saved locally and nothing is sent to the server.
  final bool Function()? isIncognito;

  Timer? _debounce;
  int? _pendingPage;

  void onPageChanged(int pageIndex) {
    _debounce?.cancel();
    _pendingPage = pageIndex;
    _debounce = Timer(debounceDuration, () => _persist(pageIndex));
  }

  Future<void> _persist(int pageIndex) async {
    _pendingPage = null;
    if (isIncognito?.call() ?? false) return;
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

  /// Persists a page change still waiting out its debounce. Without this,
  /// closing the reader (or hopping to the next chapter) within the debounce
  /// window would drop the final position, including the "read" mark.
  void flush() {
    final page = _pendingPage;
    if (page == null) return;
    _debounce?.cancel();
    _persist(page);
  }

  void dispose() {
    _debounce?.cancel();
  }
}
