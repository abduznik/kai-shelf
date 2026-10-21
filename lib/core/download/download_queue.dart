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
///
/// Besides driving downloads, the queue owns the management operations the
/// Downloads screen needs: [cancel], [retry], [remove] and [clearFinished].
class DownloadQueue extends Notifier<List<DownloadTask>> {
  static const _maxConcurrentChapters = 2;
  static const _maxConcurrentPagesPerChapter = 3;

  final DownloadWorker _worker = DownloadWorker();
  DownloadedChaptersRepository? _repository;
  int _activeChapterDownloads = 0;
  final List<_QueuedDownload> _pendingQueue = [];

  /// Chapters whose runners are currently executing, keyed by task key, so a
  /// cancel can flag a download that has already left [_pendingQueue].
  final Map<String, _QueuedDownload> _running = {};

  /// Source page list per task key, kept so a failed task can be re-driven
  /// by [retry] with the original URLs and auth headers.
  final Map<String, List<KsPage>> _sourcePages = {};

  bool _disposed = false;

  @override
  List<DownloadTask> build() {
    ref.onDispose(() {
      _disposed = true;
      _worker.dispose();
    });
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

    _sourcePages[_taskKey(serverId, chapterId)] = pages;
    state = [...state, task];
    _pendingQueue.add(_QueuedDownload(task: task, pages: pages));
    _maybeStartNext();
  }

  /// Stops a queued or in-flight download and drops it from the list.
  ///
  /// Partially written files are left on disk so a later re-download of the
  /// same chapter can resume them; [remove] is the destructive operation.
  void cancel({required String serverId, required String chapterId}) {
    _detachTask(serverId, chapterId);
  }

  /// Re-queues a failed task for a fresh attempt from the start.
  void retry({required String serverId, required String chapterId}) {
    final index = state
        .indexWhere((t) => t.serverId == serverId && t.chapterId == chapterId);
    if (index < 0 || state[index].status != DownloadStatus.failed) return;

    final previous = state[index];
    final task = previous.copyWith(
      status: DownloadStatus.queued,
      pages: [
        for (final page in previous.pages)
          page.copyWith(status: DownloadStatus.queued),
      ],
    );
    state = [
      for (final t in state)
        if (t.serverId == serverId && t.chapterId == chapterId) task else t,
    ];
    _pendingQueue.add(_QueuedDownload(task: task, pages: _pagesFor(previous)));
    _maybeStartNext();
  }

  /// Removes a task from the list, deletes its files from disk and drops its
  /// record from the downloaded-chapters repository.
  ///
  /// The list is updated before any file IO so the UI (and the storage
  /// figure) reacts immediately; the storage figure is refreshed again once
  /// the files are actually gone.
  Future<void> remove({
    required String serverId,
    required String mangaId,
    required String chapterId,
  }) async {
    _detachTask(serverId, chapterId);
    await _deleteChapterFiles(
      serverId: serverId,
      mangaId: mangaId,
      chapterId: chapterId,
    );
    await _deleteChapterRecord(serverId: serverId, chapterId: chapterId);
    _refreshStorageFigure();
  }

  /// Removes every finished (complete) task along with its files.
  Future<void> clearFinished() async {
    final finished = [
      for (final task in state)
        if (task.status == DownloadStatus.complete) task,
    ];
    if (finished.isEmpty) return;

    final finishedKeys = {
      for (final task in finished) _taskKey(task.serverId, task.chapterId),
    };
    state = [
      for (final task in state)
        if (!finishedKeys.contains(_taskKey(task.serverId, task.chapterId)))
          task,
    ];

    for (final task in finished) {
      _sourcePages.remove(_taskKey(task.serverId, task.chapterId));
      await _deleteChapterFiles(
        serverId: task.serverId,
        mangaId: task.mangaId,
        chapterId: task.chapterId,
      );
      await _deleteChapterRecord(
        serverId: task.serverId,
        chapterId: task.chapterId,
      );
    }
    _refreshStorageFigure();
  }

  /// Total bytes occupied by downloaded files on disk.
  Future<int> totalStorageBytes() => _worker.downloadsStorageBytes();

  /// Test-only: replaces the queue contents wholesale so widget tests can
  /// exercise specific task states without driving real downloads.
  void debugSetTasks(List<DownloadTask> tasks) {
    _pendingQueue.clear();
    _running.clear();
    _sourcePages.clear();
    state = [...tasks];
  }

  static String _taskKey(String serverId, String chapterId) =>
      '$serverId/$chapterId';

  /// Drops a task from every bookkeeping structure without touching disk.
  void _detachTask(String serverId, String chapterId) {
    final key = _taskKey(serverId, chapterId);
    _pendingQueue
        .removeWhere((q) => _taskKey(q.task.serverId, q.task.chapterId) == key);
    _running[key]?.cancelled = true;
    _sourcePages.remove(key);
    state = [
      for (final task in state)
        if (_taskKey(task.serverId, task.chapterId) != key) task,
    ];
  }

  List<KsPage> _pagesFor(DownloadTask task) =>
      _sourcePages[_taskKey(task.serverId, task.chapterId)] ??
      [
        for (final page in task.pages)
          KsPage(index: page.index, imageUrl: page.url),
      ];

  Future<void> _deleteChapterFiles({
    required String serverId,
    required String mangaId,
    required String chapterId,
  }) async {
    try {
      await _worker.deleteChapterDirectory(
        serverId: serverId,
        mangaId: mangaId,
        chapterId: chapterId,
      );
    } catch (_) {
      // The task is already out of the queue; a failed delete must not break
      // the UI. Whatever files remain keep counting towards the storage figure.
    }
  }

  Future<void> _deleteChapterRecord({
    required String serverId,
    required String chapterId,
  }) async {
    try {
      await _repository?.delete(serverId: serverId, chapterId: chapterId);
    } catch (_) {
      // Best effort: the on-disk files are what actually occupy storage.
    }
  }

  /// Re-scans the downloads folder after files were actually deleted, since
  /// the watch-triggered scan may have raced the deletion.
  void _refreshStorageFigure() {
    try {
      ref.invalidate(downloadsStorageProvider);
    } catch (_) {
      // The queue can already be disposed when a late file delete settles.
    }
  }

  void _maybeStartNext() {
    if (_disposed) return;
    while (_activeChapterDownloads < _maxConcurrentChapters &&
        _pendingQueue.isNotEmpty) {
      final next = _pendingQueue.removeAt(0);
      _activeChapterDownloads++;
      unawaited(_runChapterDownload(next));
    }
  }

  Future<void> _runChapterDownload(_QueuedDownload queued) async {
    final key = _taskKey(queued.task.serverId, queued.task.chapterId);
    _running[key] = queued;
    try {
      if (_disposed || queued.cancelled) return;

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
            if (queued.cancelled) return;
            final localPath = p.join(chapterDir, '${page.index}.jpg');
            await _worker.downloadPage(
                url: page.imageUrl,
                headers: page.extraHeaders,
                localPath: localPath);
            if (!queued.cancelled) {
              _updatePage(queued.task.serverId, queued.task.chapterId,
                  page.index, DownloadStatus.complete);
            }
          } catch (_) {
            failed = true;
            if (!queued.cancelled) {
              _updatePage(queued.task.serverId, queued.task.chapterId,
                  page.index, DownloadStatus.failed);
            }
          } finally {
            semaphore.release();
          }
        }),
      );

      // Cancelled mid-flight: leave the task out of the list and out of the
      // downloaded-chapters record — the user asked us to stop.
      if (queued.cancelled) return;

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
    } finally {
      _running.remove(key);
      _activeChapterDownloads--;
      _maybeStartNext();
    }
  }

  void _updateTask(String serverId, String chapterId,
      {required DownloadStatus status}) {
    if (_disposed) return;
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
    if (_disposed) return;
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
  _QueuedDownload({required this.task, required this.pages});

  final DownloadTask task;
  final List<KsPage> pages;

  /// Flipped by [DownloadQueue.cancel]/[DownloadQueue.remove] once the
  /// download has left the pending queue and its runner is executing.
  bool cancelled = false;
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

/// Total bytes occupied by files under the downloads directory.
///
/// Watches [downloadQueueProvider] so the figure re-scans whenever tasks
/// change (downloads finishing, tasks being removed), and can be explicitly
/// invalidated by the queue once deletions really hit the disk.
final downloadsStorageProvider = FutureProvider<int>((ref) {
  ref.watch(downloadQueueProvider);
  return ref.read(downloadQueueProvider.notifier).totalStorageBytes();
});
