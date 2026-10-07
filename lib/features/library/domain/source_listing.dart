import '../../../core/backend/models.dart';
import '../../../core/backend/server_backend.dart';

/// One source's slot in a multi-source request: empty until it answers, then
/// holds either its items or the error it failed with.
class SourceListing {
  SourceListing(this.source);

  final KsSource source;
  List<KsSourceManga>? items;
  Object? error;

  bool get done => items != null || error != null;
}

/// Fills [listings] by browsing each source, [parallelism] at a time, so a
/// slow or broken source cannot block the rest. [onProgress] fires after each
/// source settles; stop early by returning true from [cancelled] (e.g. the
/// screen was disposed or a newer request superseded this one).
Future<void> loadSourceListings(
  SourceCapableBackend backend,
  List<SourceListing> listings, {
  required SourceBrowseMode mode,
  String query = '',
  int parallelism = 4,
  bool Function()? cancelled,
  void Function()? onProgress,
}) async {
  var next = 0;
  Future<void> worker() async {
    while (next < listings.length) {
      final l = listings[next++];
      try {
        final page =
            await backend.browseSource(l.source.id, mode: mode, query: query);
        l.items = page.items;
      } catch (e) {
        l.error = e;
      }
      if (cancelled?.call() ?? false) return;
      onProgress?.call();
    }
  }

  await Future.wait([for (var i = 0; i < parallelism; i++) worker()]);
}
