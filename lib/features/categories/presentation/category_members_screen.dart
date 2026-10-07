import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/category_providers.dart';
import '../../library/presentation/widgets/manga_grid_tile.dart';

/// The manga inside one category or collection.
class CategoryMembersScreen extends ConsumerWidget {
  const CategoryMembersScreen(
      {super.key, required this.categoryId, required this.name});

  final String categoryId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mangaAsync = ref.watch(categoryMangaProvider(categoryId));
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: mangaAsync.when(
        data: (list) => list.isEmpty
            ? const Center(child: Text('Nothing here yet.'))
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.62,
                ),
                itemCount: list.length,
                itemBuilder: (context, index) => MangaGridTile(
                  manga: list[index],
                  onTap: () => context.push('/manga/${list[index].id}'),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
      ),
    );
  }
}
