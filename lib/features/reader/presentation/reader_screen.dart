import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/models.dart';
import '../../../core/download/download_queue.dart';
import '../../../core/download/offline_page_resolver.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/library_providers.dart';
import '../../../core/providers/reader_prefs_provider.dart';
import '../../../core/providers/storage_providers.dart';
import '../domain/page_prefetcher.dart';
import '../domain/reader_progress_tracker.dart';
import 'paged_reader_view.dart';
import 'webtoon_reader_view.dart';
import 'widgets/reader_controls_overlay.dart';

/// Chapters below this page count are cheap enough to eagerly download in
/// the background alongside the current chapter, so paging into the next
/// chapter can start from local files immediately.
const _smallChapterPageThreshold = 25;

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen(
      {super.key, required this.mangaId, required this.chapterId});

  final String mangaId;
  final String chapterId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _controlsVisible = false;
  int _currentPage = 0;
  ReaderProgressTracker? _tracker;
  final PagePrefetcher _prefetcher = PagePrefetcher();
  bool _backgroundDownloadTriggered = false;

  @override
  void dispose() {
    _tracker?.dispose();
    super.dispose();
  }

  /// Downloads the rest of the chapter currently being read in the
  /// background (so offlinePagesProvider can serve local files on a
  /// future re-open), and, if the very next chapter is small enough, kicks
  /// off its download too so paging across a chapter boundary can also
  /// come from disk. Web has no durable filesystem, so this is native-only,
  /// matching the existing download-feature guard.
  Future<void> _maybeStartBackgroundDownload() async {
    if (_backgroundDownloadTriggered || kIsWeb) return;
    _backgroundDownloadTriggered = true;

    final connection = ref.read(activeConnectionProvider);
    final backend = ref.read(activeBackendProvider);
    if (connection == null || backend == null) return;

    final repository = ref.read(downloadedChaptersRepositoryProvider);
    final queue = ref.read(downloadQueueProvider.notifier);
    queue.attachRepository(repository);

    final manga = await ref.read(mangaDetailProvider(widget.mangaId).future);

    Future<void> enqueueChapter(KsChapter chapter) async {
      final alreadyDownloaded = repository != null &&
          await repository.find(
                  serverId: connection.serverId, chapterId: chapter.id) !=
              null;
      if (alreadyDownloaded) return;
      final pages = await backend.getPages(chapter.id);
      queue.enqueue(
        serverId: connection.serverId,
        mangaId: widget.mangaId,
        chapterId: chapter.id,
        mangaTitle: manga.title,
        chapterTitle: chapter.title,
        pages: pages,
      );
    }

    final currentChapter = await ref
        .read(chaptersProvider(widget.mangaId).future)
        .then((chapters) => chapters.where((c) => c.id == widget.chapterId));
    if (currentChapter.isEmpty) return;
    await enqueueChapter(currentChapter.first);

    final chapters = await ref.read(chaptersProvider(widget.mangaId).future);
    final index = chapters.indexWhere((c) => c.id == widget.chapterId);
    if (index == -1 || index + 1 >= chapters.length) return;
    final nextChapter = chapters[index + 1];
    if (nextChapter.pageCount != null &&
        nextChapter.pageCount! <= _smallChapterPageThreshold) {
      await enqueueChapter(nextChapter);
    }
  }

  void _ensureTracker(int totalPages) {
    if (_tracker != null) return;
    final connection = ref.read(activeConnectionProvider);
    if (connection == null) return;
    final repository = ref.read(readingProgressRepositoryProvider);
    final backend = ref.read(activeBackendProvider);

    _tracker = ReaderProgressTracker(
      totalPages: totalPages,
      onSaveLocal: ({required read, required lastPageRead}) async {
        await repository?.save(
          serverId: connection.serverId,
          mangaId: widget.mangaId,
          chapterId: widget.chapterId,
          read: read,
          lastPageRead: lastPageRead,
        );
      },
      onSyncServer: backend == null
          ? null
          : ({required read, required lastPageRead}) =>
              backend.updateReadProgress(
                widget.chapterId,
                read: read,
                lastPageRead: lastPageRead,
              ),
    );
  }

  void _onPageChanged(int index, List<KsPage> pages) {
    setState(() => _currentPage = index);
    _tracker?.onPageChanged(index);
    _prefetcher.prefetchAround(context, pages, index);
  }

  @override
  Widget build(BuildContext context) {
    final pagesAsync = ref.watch(offlinePagesProvider(widget.chapterId));
    final mode = ref.watch(readerModeProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: pagesAsync.when(
        data: (pages) {
          if (pages.isEmpty) {
            return const Center(
              child: Text('No pages found for this chapter.',
                  style: TextStyle(color: Colors.white)),
            );
          }
          _ensureTracker(pages.length);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _prefetcher.prefetchAround(context, pages, _currentPage);
            _maybeStartBackgroundDownload();
          });

          return Stack(
            children: [
              GestureDetector(
                onTap: () =>
                    setState(() => _controlsVisible = !_controlsVisible),
                child: mode == ReaderMode.paged
                    ? PagedReaderView(
                        pages: pages,
                        onPageChanged: (index) =>
                            _onPageChanged(index, pages))
                    : WebtoonReaderView(
                        pages: pages,
                        onPageChanged: (index) =>
                            _onPageChanged(index, pages)),
              ),
              ReaderControlsOverlay(
                visible: _controlsVisible,
                currentPage: _currentPage,
                totalPages: pages.length,
                mode: mode,
                onModeChanged: (newMode) =>
                    ref.read(readerModeProvider.notifier).setMode(newMode),
                onClose: () => Navigator.of(context).maybePop(),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Failed to load pages: $error',
              style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}
