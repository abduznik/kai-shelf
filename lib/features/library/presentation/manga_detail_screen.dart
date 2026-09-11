import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/models.dart';
import '../../../core/download/download_queue.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/chapter_sort_provider.dart';
import '../../../core/providers/library_providers.dart';
import '../../../core/providers/storage_providers.dart';
import '../../../core/widgets/authenticated_image.dart';
import '../../downloads/presentation/widgets/download_chapter_button.dart';

class MangaDetailScreen extends ConsumerWidget {
  const MangaDetailScreen({super.key, required this.mangaId});

  final String mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mangaAsync = ref.watch(mangaDetailProvider(mangaId));
    final chaptersAsync = ref.watch(chaptersProvider(mangaId));
    final sortOrder = ref.watch(chapterSortProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manga'),
        actions: [
          IconButton(
            tooltip: sortOrder == ChapterSortOrder.descending
                ? 'Newest first'
                : 'Oldest first',
            icon: Icon(sortOrder == ChapterSortOrder.descending
                ? Icons.arrow_downward
                : Icons.arrow_upward),
            onPressed: () =>
                ref.read(chapterSortProvider.notifier).toggle(),
          ),
          chaptersAsync.maybeWhen(
            data: (chapters) => mangaAsync.maybeWhen(
              data: (manga) => PopupMenuButton<_BatchDownloadOption>(
                tooltip: 'Batch download',
                onSelected: (option) => _downloadBatch(
                  context,
                  ref,
                  manga: manga,
                  chapters: _sorted(chapters, sortOrder),
                  option: option,
                ),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _BatchDownloadOption.all,
                    child: Text('Download all chapters'),
                  ),
                  PopupMenuItem(
                    value: _BatchDownloadOption.next5,
                    child: Text('Download next 5 chapters'),
                  ),
                  PopupMenuItem(
                    value: _BatchDownloadOption.next10,
                    child: Text('Download next 10 chapters'),
                  ),
                ],
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: mangaAsync.when(
        data: (manga) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _MangaHeader(manga: manga)),
            chaptersAsync.when(
              data: (chapters) {
                if (chapters.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No chapters found.')),
                    ),
                  );
                }
                final sortedChapters = _sorted(chapters, sortOrder);
                return SliverPadding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 88,
                  ),
                  sliver: SliverList.builder(
                    itemCount: sortedChapters.length,
                    itemBuilder: (context, index) {
                      final chapter = sortedChapters[index];
                      return ListTile(
                        leading: Icon(
                          chapter.read
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: chapter.read
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                        title: Text(chapter.title),
                        subtitle: chapter.uploadDate != null
                            ? Text(_formatDate(chapter.uploadDate!))
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: chapter.read
                                  ? 'Mark as unread'
                                  : 'Mark as read',
                              icon: Icon(chapter.read
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined),
                              onPressed: () => _toggleRead(ref, chapter),
                            ),
                            DownloadChapterButton(
                              mangaId: mangaId,
                              mangaTitle: manga.title,
                              chapter: chapter,
                            ),
                          ],
                        ),
                        onTap: () =>
                            context.push('/reader/$mangaId/${chapter.id}'),
                      );
                    },
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text('Failed to load chapters: $error')),
                ),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Failed to load manga: $error')),
      ),
    );
  }

  List<KsChapter> _sorted(List<KsChapter> chapters, ChapterSortOrder order) {
    final sorted = [...chapters]
      ..sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
    if (order == ChapterSortOrder.descending) return sorted.reversed.toList();
    return sorted;
  }

  Future<void> _toggleRead(WidgetRef ref, KsChapter chapter) async {
    final backend = ref.read(activeBackendProvider);
    if (backend == null) return;
    await backend.updateReadProgress(chapter.id, read: !chapter.read);
    ref.invalidate(chaptersProvider(mangaId));
  }

  Future<void> _downloadBatch(
    BuildContext context,
    WidgetRef ref, {
    required KsManga manga,
    required List<KsChapter> chapters,
    required _BatchDownloadOption option,
  }) async {
    final connection = ref.read(activeConnectionProvider);
    final backend = ref.read(activeBackendProvider);
    if (connection == null || backend == null) return;

    final unreadFirst = chapters.where((c) => !c.read).toList();
    final targets = switch (option) {
      _BatchDownloadOption.all => chapters,
      _BatchDownloadOption.next5 => unreadFirst.take(5).toList(),
      _BatchDownloadOption.next10 => unreadFirst.take(10).toList(),
    };

    if (targets.isEmpty) return;

    final repository = ref.read(downloadedChaptersRepositoryProvider);
    final queue = ref.read(downloadQueueProvider.notifier);
    queue.attachRepository(repository);

    for (final chapter in targets) {
      final pages = await backend.getPages(chapter.id);
      queue.enqueue(
        serverId: connection.serverId,
        mangaId: mangaId,
        chapterId: chapter.id,
        mangaTitle: manga.title,
        chapterTitle: chapter.title,
        pages: pages,
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queued ${targets.length} chapter(s) for download')),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

enum _BatchDownloadOption { all, next5, next10 }

class _MangaHeader extends StatelessWidget {
  const _MangaHeader({required this.manga});

  final KsManga manga;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 100,
              height: 150,
              child: manga.coverUrl != null
                  ? AuthenticatedImage(
                      imageUrl: manga.coverUrl!,
                      headers: manga.coverHeaders,
                      fit: BoxFit.cover)
                  : Container(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.menu_book_outlined),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(manga.title,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (manga.genres.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final genre in manga.genres)
                        Chip(
                          label:
                              Text(genre, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                if (manga.description != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    manga.description!,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
