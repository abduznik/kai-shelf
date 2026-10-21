import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/download/byte_format.dart';
import '../../../core/download/download_queue.dart';
import '../../../core/download/download_task.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadQueueProvider);
    final hasFinished =
        tasks.any((task) => task.status == DownloadStatus.complete);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (hasFinished)
            IconButton(
              tooltip: 'Clear finished',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmClearFinished(context, ref, tasks),
            ),
        ],
      ),
      body: Column(
        children: [
          const _StorageSummaryTile(),
          Expanded(
            child: tasks.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) =>
                        _TaskTile(task: tasks[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearFinished(
    BuildContext context,
    WidgetRef ref,
    List<DownloadTask> tasks,
  ) async {
    final queue = ref.read(downloadQueueProvider.notifier);
    final finishedCount =
        tasks.where((task) => task.status == DownloadStatus.complete).length;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Clear finished downloads?'),
            content: Text(
              'Removes $finishedCount finished '
              'download${finishedCount == 1 ? '' : 's'} and their files '
              'from disk.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    await queue.clearFinished();
  }
}

/// Summary row showing how much disk space the downloads occupy.
class _StorageSummaryTile extends ConsumerWidget {
  const _StorageSummaryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // valueOrNull keeps the last known figure visible while a re-scan is in
    // flight, so the number never flickers away mid-delete.
    final bytes = ref.watch(downloadsStorageProvider).valueOrNull;
    return ListTile(
      leading: const Icon(Icons.storage_outlined),
      title: const Text('Storage used'),
      trailing: Text(bytes == null ? '…' : formatBytes(bytes)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.download_outlined, size: 56, color: outline),
          const SizedBox(height: 12),
          const Text('No downloads yet.'),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(task.mangaTitle),
      subtitle: Text(task.chapterTitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusIndicator(task: task),
          const SizedBox(width: 8),
          _TaskAction(task: task),
        ],
      ),
    );
  }
}

/// The one action available for the task's current state: cancel while it is
/// queued or downloading, retry after a failure, remove once it is finished.
class _TaskAction extends ConsumerWidget {
  const _TaskAction({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (task.status) {
      case DownloadStatus.queued:
      case DownloadStatus.downloading:
      case DownloadStatus.paused:
        return IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
          onPressed: () => ref
              .read(downloadQueueProvider.notifier)
              .cancel(serverId: task.serverId, chapterId: task.chapterId),
        );
      case DownloadStatus.failed:
        return IconButton(
          tooltip: 'Retry',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref
              .read(downloadQueueProvider.notifier)
              .retry(serverId: task.serverId, chapterId: task.chapterId),
        );
      case DownloadStatus.complete:
        return IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _confirmRemove(context, ref, task),
        );
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    DownloadTask task,
  ) async {
    final queue = ref.read(downloadQueueProvider.notifier);

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete download?'),
            content: Text(
              'This permanently deletes the downloaded files for '
              '"${task.chapterTitle}".',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    await queue.remove(
      serverId: task.serverId,
      mangaId: task.mangaId,
      chapterId: task.chapterId,
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    switch (task.status) {
      case DownloadStatus.queued:
        return const Icon(Icons.schedule);
      case DownloadStatus.downloading:
        return SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(value: task.progress),
        );
      case DownloadStatus.complete:
        return Icon(Icons.check_circle,
            color: Theme.of(context).colorScheme.primary);
      case DownloadStatus.failed:
        return Icon(Icons.error, color: Theme.of(context).colorScheme.error);
      case DownloadStatus.paused:
        return const Icon(Icons.pause_circle_outline);
    }
  }
}
