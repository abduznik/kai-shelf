import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/models.dart';
import '../../../../core/download/download_queue.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../../core/providers/storage_providers.dart';

class DownloadChapterButton extends ConsumerWidget {
  const DownloadChapterButton({
    super.key,
    required this.mangaId,
    required this.mangaTitle,
    required this.chapter,
  });

  final String mangaId;
  final String mangaTitle;
  final KsChapter chapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const SizedBox.shrink();

    return IconButton(
      icon: const Icon(Icons.download_outlined),
      tooltip: 'Download chapter',
      onPressed: () async {
        final connection = ref.read(activeConnectionProvider);
        final backend = ref.read(activeBackendProvider);
        if (connection == null || backend == null) return;

        final repository = ref.read(downloadedChaptersRepositoryProvider);
        ref.read(downloadQueueProvider.notifier).attachRepository(repository);

        final pages = await backend.getPages(chapter.id);
        ref.read(downloadQueueProvider.notifier).enqueue(
              serverId: connection.serverId,
              mangaId: mangaId,
              chapterId: chapter.id,
              mangaTitle: mangaTitle,
              chapterTitle: chapter.title,
              pages: pages,
            );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloading "${chapter.title}"')),
          );
        }
      },
    );
  }
}
