import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/models.dart';
import '../../../core/providers/library_providers.dart';
import '../../downloads/presentation/widgets/download_chapter_button.dart';

class MangaDetailScreen extends ConsumerWidget {
  const MangaDetailScreen({super.key, required this.mangaId});

  final String mangaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mangaAsync = ref.watch(mangaDetailProvider(mangaId));
    final chaptersAsync = ref.watch(chaptersProvider(mangaId));

    return Scaffold(
      appBar: AppBar(title: const Text('Manga')),
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
                return SliverList.builder(
                  itemCount: chapters.length,
                  itemBuilder: (context, index) {
                    final chapter = chapters[index];
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
                      trailing: DownloadChapterButton(
                        mangaId: mangaId,
                        mangaTitle: manga.title,
                        chapter: chapter,
                      ),
                      onTap: () =>
                          context.push('/reader/$mangaId/${chapter.id}'),
                    );
                  },
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

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
                  ? CachedNetworkImage(
                      imageUrl: manga.coverUrl!, fit: BoxFit.cover)
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
