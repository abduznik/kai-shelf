import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/server_backend.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/library_providers.dart';
import 'widgets/manga_grid_tile.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String? _selectedLibraryId;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(activeBackendProvider);

    if (backend == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Library')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Not connected to a server yet.'),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Connect')),
            ],
          ),
        ),
      );
    }

    final librariesAsync = ref.watch(libraryListProvider);
    final mangaAsync = ref.watch(
      mangaListProvider(
        MangaListParams(
          libraryId: _selectedLibraryId,
          searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          if (backend is SourceCapableBackend)
            IconButton(
              icon: const Icon(Icons.explore_outlined),
              tooltip: 'Discover new manga',
              onPressed: () => context.push('/discover'),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search library',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          librariesAsync.when(
            data: (libraries) {
              if (libraries.length <= 1) return const SizedBox.shrink();
              return SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _selectedLibraryId == null,
                        onSelected: (_) =>
                            setState(() => _selectedLibraryId = null),
                      ),
                    ),
                    for (final library in libraries)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label:
                              Text('${library.name} (${library.mangaCount})'),
                          selected: _selectedLibraryId == library.id,
                          onSelected: (_) =>
                              setState(() => _selectedLibraryId = library.id),
                        ),
                      ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
          Expanded(
            child: mangaAsync.when(
              data: (mangaList) {
                if (mangaList.isEmpty) {
                  return const Center(child: Text('No manga found.'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(
                      mangaListProvider(
                        MangaListParams(
                          libraryId: _selectedLibraryId,
                          searchQuery:
                              _searchQuery.isEmpty ? null : _searchQuery,
                        ),
                      ),
                    );
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 160,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: mangaList.length,
                    itemBuilder: (context, index) {
                      final manga = mangaList[index];
                      return MangaGridTile(
                        manga: manga,
                        onTap: () => context.push('/manga/${manga.id}'),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('Failed to load library: $error')),
            ),
          ),
        ],
      ),
    );
  }
}
