import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../backend/models.dart';
import 'download_task.dart';
import 'download_worker.dart';
import 'downloaded_chapters_repository.dart';

/// Holds all in-flight/queued/completed download tasks for the session and
/// drives them through the worker with capped concurrency: at most 2
/// chapters downloading at once, at most 3 pages within a chapter.
class DownloadQueue extends Notifier<List<DownloadTask>> {
  static const _maxConcurrentChapters = 2;
  static const _maxConcurrentPagesPerChapter = 3;

  final DownloadWorker _worker = DownloadWorker();
  DownloadedChaptersRepository? _repository;
  int _activeChapterDownloads = 0;
  final List<_QueuedDownload> _pendingQueue = [];

  @override
  List<DownloadTask> build() {
    ref.onDispose(_worker.dispose);
    return [];
  }

  void attachRepository(DownloadedChaptersRepository? repository) {
    _repository = repository;
  }

  void enqueue({
    required String serverId,
    required String mangaId,
    required String chapterId,
    required String mangaTitle,
    required String chapterTitle,
    required List<KsPage> pages,
  }) {
    final alreadyQueued = state.any(
      (t) =>
          t.serverId == serverId &&
          t.chapterId == chapterId &&
          t.status != DownloadStatus.failed,
    );
    if (alreadyQueued) return;

    final task = DownloadTask(
      serverId: serverId,
      mangaId: mangaId,
      chapterId: chapterId,
      mangaTitle: mangaTitle,
      chapterTitle: chapterTitle,
      pages: pages
          .map((page) =>
              PageDownloadState(index: page.index, url: page.imageUrl))
          .toList(),
    );

    state = [...state, task];
    _pendingQueue.add(_QueuedDownload(task: task, pages: pages));
    _maybeStartNext();
  }

  void _maybeStartNext() {
    while (_activeChapterDownloads < _maxConcurrentChapters &&
        _pendingQueue.isNotEmpty) {
      final next = _pendingQueue.removeAt(0);
      _activeChapterDownloads++;
      unawaited(_runChapterDownload(next));
    }
  }

  Future<void> _runChapterDownload(_QueuedDownload queued) async {
    _updateTask(queued.task.serverId, queued.task.chapterId,
        status: DownloadStatus.downloading);

    final chapterDir = await _worker.chapterDirectoryPath(
      serverId: queued.task.serverId,
      mangaId: queued.task.mangaId,
      chapterId: queued.task.chapterId,
    );

    var failed = false;
    final semaphore = _Semaphore(_maxConcurrentPagesPerChapter);
    await Future.wait(
      queued.pages.map((page) async {
        await semaphore.acquire();
        try {
          final localPath = p.join(chapterDir, '${page.index}.jpg');
          await _worker.downloadPage(
              url: page.imageUrl,
              headers: page.extraHeaders,
              localPath: localPath);
          _updatePage(queued.task.serverId, queued.task.chapterId, page.index,
              DownloadStatus.complete);
        } catch (_) {
          failed = true;
          _updatePage(queued.task.serverId, queued.task.chapterId, page.index,
              DownloadStatus.failed);
        } finally {
          semaphore.release();
        }
      }),
    );

    final finalStatus =
        failed ? DownloadStatus.failed : DownloadStatus.complete;
    _updateTask(queued.task.serverId, queued.task.chapterId,
        status: finalStatus);

    await _repository?.upsert(
      serverId: queued.task.serverId,
      mangaId: queued.task.mangaId,
      chapterId: queued.task.chapterId,
      localPath: chapterDir,
      status: finalStatus,
      pageCount: queued.pages.length,
    );

    _activeChapterDownloads--;
    _maybeStartNext();
  }

  void _updateTask(String serverId, String chapterId,
      {required DownloadStatus status}) {
    state = [
      for (final task in state)
        if (task.serverId == serverId && task.chapterId == chapterId)
          task.copyWith(status: status)
        else
          task,
    ];
  }

  void _updatePage(
      String serverId, String chapterId, int pageIndex, DownloadStatus status) {
    state = [
      for (final task in state)
        if (task.serverId == serverId && task.chapterId == chapterId)
          task.copyWith(
            pages: [
              for (final page in task.pages)
                if (page.index == pageIndex)
                  page.copyWith(status: status)
                else
                  page,
            ],
          )
        else
          task,
    ];
  }
}

class _QueuedDownload {
  const _QueuedDownload({required this.task, required this.pages});
  final DownloadTask task;
  final List<KsPage> pages;
}

/// Minimal counting semaphore for bounding concurrent page downloads
/// within one chapter — no external dependency needed for this.
class _Semaphore {
  _Semaphore(this._maxCount) : _currentCount = _maxCount;

  final int _maxCount;
  int _currentCount;
  final List<Completer<void>> _waiters = [];

  Future<void> acquire() {
    if (_currentCount > 0) {
      _currentCount--;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final completer = _waiters.removeAt(0);
      completer.complete();
    } else {
      _currentCount = (_currentCount + 1).clamp(0, _maxCount);
    }
  }
}

final downloadQueueProvider =
    NotifierProvider<DownloadQueue, List<DownloadTask>>(
  DownloadQueue.new,
);
