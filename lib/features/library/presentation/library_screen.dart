import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/models.dart';
import '../../../core/backend/server_backend.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/library_providers.dart';
import '../../../core/widgets/incognito_badge.dart';
import '../domain/library_filter.dart';
import 'library_filter_provider.dart';
import 'widgets/library_filter_sheet.dart';
import 'widgets/manga_grid_tile.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String? _selectedLibraryId;

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(activeBackendProvider);
    // Filter state lives in a provider, not here, so the title screen's
    // genre chips can hand a genre over and land on a filtered library.
    final filter = ref.watch(libraryFilterProvider);

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
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          const IncognitoBadge(),
          IconButton(
            icon: Badge(
              isLabelVisible: filter.activeCount > 0,
              label: Text('${filter.activeCount}'),
              child:
                  const Icon(Icons.filter_list, semanticLabel: 'Sort & filter'),
            ),
            tooltip: 'Sort & filter',
            onPressed: () => _openFilters(mangaAsync.valueOrNull ?? const []),
          ),
          if (backend is CategoryCapableBackend)
            IconButton(
              icon: Icon(Icons.label_outline,
                  semanticLabel:
                      'Manage ${(backend as CategoryCapableBackend).categoryNounPlural}'),
              tooltip:
                  'Manage ${(backend as CategoryCapableBackend).categoryNounPlural}',
              onPressed: () => context.push('/categories'),
            ),
          if (backend is SourceCapableBackend)
            IconButton(
              icon: const Icon(Icons.auto_awesome_outlined,
                  semanticLabel: 'Recommended for you'),
              tooltip: 'Recommended for you',
              onPressed: () => context.push('/recommended'),
            ),
          if (backend is SourceCapableBackend)
            IconButton(
              icon: const Icon(Icons.explore_outlined,
                  semanticLabel: 'Discover new manga'),
              tooltip: 'Discover new manga',
              onPressed: () => context.push('/discover'),
            ),
          if (backend is ExtensionCapableBackend)
            IconButton(
              icon: const Icon(Icons.extension_outlined,
                  semanticLabel: 'Extensions'),
              tooltip: 'Extensions',
              onPressed: () => context.push('/extensions'),
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
              onChanged: (value) {
                final notifier = ref.read(libraryFilterProvider.notifier);
                notifier.state = notifier.state.copyWith(query: value);
              },
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
                          // OPDS catalogs can't count a category's titles
                          // without fetching every page of it, so they report
                          // 0 — showing that would read as "empty category".
                          label: Text(library.mangaCount > 0
                              ? '${library.name} (${library.mangaCount})'
                              : library.name),
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
              data: (allManga) {
                final mangaList = filter.apply(allManga);
                if (mangaList.isEmpty) {
                  return const Center(child: Text('No manga found.'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(
                      mangaListProvider(
                        MangaListParams(
                          libraryId: _selectedLibraryId,
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

  Future<void> _openFilters(List<KsManga> all) async {
    final result = await showModalBottomSheet<LibraryFilter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LibraryFilterSheet(
          initial: ref.read(libraryFilterProvider),
          genres: LibraryFilter.genresOf(all)),
    );
    if (result != null) ref.read(libraryFilterProvider.notifier).state = result;
  }
}
