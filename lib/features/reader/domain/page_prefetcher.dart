import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../core/backend/models.dart';

/// Warms the shared CachedNetworkImage disk/memory cache for a lookahead
/// window of upcoming pages, so paging forward feels instant instead of
/// showing the network placeholder every time. Downloaded (local) pages
/// and pages already covered by a previous call are skipped.
class PagePrefetcher {
  PagePrefetcher({this.lookahead = 3});

  final int lookahead;
  final Set<String> _prefetched = {};

  void prefetchAround(BuildContext context, List<KsPage> pages, int currentIndex) {
    final end = (currentIndex + lookahead).clamp(0, pages.length - 1);
    for (var i = currentIndex; i <= end; i++) {
      final page = pages[i];
      if (page.isLocal) continue;
      if (!_prefetched.add(page.imageUrl)) continue;

      // On web, headers aren't respected by CachedNetworkImage's fetcher
      // (see AuthenticatedImage) — skip prefetching those; the browser's
      // own HTTP cache still helps once PageImage's manual fetch runs.
      if (kIsWeb && page.extraHeaders != null && page.extraHeaders!.isNotEmpty) {
        continue;
      }

      precacheImage(
        CachedNetworkImageProvider(page.imageUrl, headers: page.extraHeaders),
        context,
      ).catchError((_) {
        // Best-effort — a failed prefetch just means PageImage will fetch
        // it normally when the user actually reaches that page.
      });
    }
  }
}
