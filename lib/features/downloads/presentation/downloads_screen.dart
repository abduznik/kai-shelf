import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/download/download_queue.dart';
import '../../../core/download/download_task.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadQueueProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: tasks.isEmpty
          ? const Center(child: Text('No downloads yet.'))
          : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return ListTile(
                  title: Text(task.mangaTitle),
                  subtitle: Text(task.chapterTitle),
                  trailing: _StatusIndicator(task: task),
                );
              },
            ),
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
