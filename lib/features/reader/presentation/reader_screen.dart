import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/models.dart';
import '../../../core/download/download_queue.dart';
import '../../../core/download/offline_page_resolver.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/incognito_provider.dart';
import '../../../core/providers/library_providers.dart';
import '../../../core/providers/reader_prefs_provider.dart';
import '../../../core/providers/storage_providers.dart';
import '../../../core/storage/reading_progress_repository.dart';
import '../domain/page_prefetcher.dart';
import '../domain/reader_progress_tracker.dart';
import '../domain/reading_flow.dart';
import 'package:go_router/go_router.dart';
import 'reader_jump_controller.dart';
import '../../../core/widgets/incognito_badge.dart';
import 'paged_reader_view.dart';
import 'webtoon_reader_view.dart';
import 'widgets/next_chapter_prompt.dart';
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
  int? _startPage;
  bool _resolvingStart = false;
  final ReaderJumpController _jumpController = ReaderJumpController();
  ReaderProgressTracker? _tracker;
  final PagePrefetcher _prefetcher = PagePrefetcher();
  bool _backgroundDownloadTriggered = false;

  @override
  void dispose() {
    // Flush so leaving quickly (or hopping to the next chapter) still
    // records where the user got to.
    _tracker?.flush();
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
    // Incognito: no writes to disk on the user's behalf. The trigger flag is
    // left unset so leaving incognito mid-chapter can still start it.
    if (ref.read(incognitoProvider)) return;
    if (_backgroundDownloadTriggered || kIsWeb) return;
    _backgroundDownloadTriggered = true;

    final connection = ref.read(activeConnectionProvider);
    final backend = ref.read(activeBackendProvider);
    if (connection == null || backend == null) return;

    final repository = ref.read(downloadedChaptersRepositoryProvider);
    final queue = ref.read(downloadQueueProvider.notifier);
    queue.attachRepository(repository);

    final manga = await ref.read(mangaDetailProvider(widget.mangaId).future);
    // Previews (opened from a source search, not in the library) are for
    // reading only; don't write them to disk behind the user's back.
    if (!manga.inLibrary) return;

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

  /// Resolves where to open the chapter, once. Server progress comes from
  /// the chapter list (works on web, where there is no local database); the
  /// local row is only a fallback for unsynced progress.
  Future<int> _resolveStartPage(int pageCount) async {
    // Each source is looked up independently: offline, the chapter list
    // fails but a downloaded chapter's local progress row is still there.
    KsChapter? chapter;
    try {
      final chapters = await ref.read(chaptersProvider(widget.mangaId).future);
      chapter = chapters.where((c) => c.id == widget.chapterId).firstOrNull;
    } catch (_) {}

    ReadingProgress? local;
    try {
      final connection = ref.read(activeConnectionProvider);
      if (connection != null) {
        local = await ref
            .read(readingProgressRepositoryProvider)
            ?.get(serverId: connection.serverId, chapterId: widget.chapterId);
      }
    } catch (_) {}

    return resumePageFor(
      pageCount: pageCount,
      serverRead: chapter?.read ?? false,
      serverLastPage: chapter?.lastPageRead,
      localRead: local?.read ?? false,
      localLastPage: local?.lastPageRead,
    );
  }

  void _goToChapter(KsChapter chapter) {
    context.pushReplacement('/reader/${widget.mangaId}/${chapter.id}');
  }

  void _ensureTracker(int totalPages) {
    if (_tracker != null) return;
    final connection = ref.read(activeConnectionProvider);
    if (connection == null) return;
    final repository = ref.read(readingProgressRepositoryProvider);
    final backend = ref.read(activeBackendProvider);
    final container = ProviderScope.containerOf(context, listen: false);

    _tracker = ReaderProgressTracker(
      totalPages: totalPages,
      isIncognito: () => ref.read(incognitoProvider),
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
          : ({required read, required lastPageRead}) async {
              await backend.updateReadProgress(
                widget.chapterId,
                read: read,
                lastPageRead: lastPageRead,
              );
              // Keep the detail screen's chapter list (and its continue
              // button) in step with what was just read. Goes through the
              // container because a flush on dispose lands after `ref` is
              // no longer usable.
              try {
                container.invalidate(chaptersProvider(widget.mangaId));
              } catch (_) {}
            },
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
          if (_startPage == null) {
            if (!_resolvingStart) {
              _resolvingStart = true;
              _resolveStartPage(pages.length).then((page) {
                if (!mounted) return;
                setState(() {
                  _startPage = page;
                  _currentPage = page;
                });
              });
            }
            return const Center(child: CircularProgressIndicator());
          }
          _ensureTracker(pages.length);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _prefetcher.prefetchAround(context, pages, _currentPage);
            _maybeStartBackgroundDownload();
          });

          final chapters =
              ref.watch(chaptersProvider(widget.mangaId)).value ?? const [];
          final adjacent = adjacentChapters(chapters, widget.chapterId);
          final atEnd = _currentPage >= pages.length - 1;

          return Stack(
            children: [
              GestureDetector(
                onTap: () =>
                    setState(() => _controlsVisible = !_controlsVisible),
                child: mode == ReaderMode.paged
                    ? PagedReaderView(
                        pages: pages,
                        initialPage: _currentPage,
                        jumpController: _jumpController,
                        onPageChanged: (index) => _onPageChanged(index, pages))
                    : WebtoonReaderView(
                        pages: pages,
                        initialPage: _currentPage,
                        jumpController: _jumpController,
                        onPageChanged: (index) => _onPageChanged(index, pages)),
              ),
              if (atEnd && adjacent.next != null && !_controlsVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.of(context).padding.bottom + 24,
                  child: NextChapterPrompt(
                    onPressed: () => _goToChapter(adjacent.next!),
                  ),
                ),
              const IncognitoBadge.positioned(),
              ReaderControlsOverlay(
                visible: _controlsVisible,
                currentPage: _currentPage,
                totalPages: pages.length,
                mode: mode,
                onModeChanged: (newMode) =>
                    ref.read(readerModeProvider.notifier).setMode(newMode),
                onClose: () => Navigator.of(context).maybePop(),
                onPageSelected: _jumpController.jumpTo,
                onPreviousChapter: adjacent.previous == null
                    ? null
                    : () => _goToChapter(adjacent.previous!),
                onNextChapter: adjacent.next == null
                    ? null
                    : () => _goToChapter(adjacent.next!),
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
