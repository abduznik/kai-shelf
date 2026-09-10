import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/download/offline_page_resolver.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/reader_prefs_provider.dart';
import '../../../core/providers/storage_providers.dart';
import '../domain/reader_progress_tracker.dart';
import 'paged_reader_view.dart';
import 'webtoon_reader_view.dart';
import 'widgets/reader_controls_overlay.dart';

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

  @override
  void dispose() {
    _tracker?.dispose();
    super.dispose();
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

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _tracker?.onPageChanged(index);
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

          return Stack(
            children: [
              GestureDetector(
                onTap: () =>
                    setState(() => _controlsVisible = !_controlsVisible),
                child: mode == ReaderMode.paged
                    ? PagedReaderView(
                        pages: pages, onPageChanged: _onPageChanged)
                    : WebtoonReaderView(
                        pages: pages, onPageChanged: _onPageChanged),
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
