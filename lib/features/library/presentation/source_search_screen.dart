import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/models.dart';
import '../../../core/backend/server_backend.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/source_providers.dart';
import '../../../core/widgets/authenticated_image.dart';

/// Searches one source's catalog and lets the user add a result straight
/// to their library. Distinct from the in-library LibraryScreen search,
/// which only filters manga already added.
class SourceSearchScreen extends ConsumerStatefulWidget {
  const SourceSearchScreen(
      {super.key, required this.sourceId, required this.sourceName});

  final String sourceId;
  final String sourceName;

  @override
  ConsumerState<SourceSearchScreen> createState() => _SourceSearchScreenState();
}

class _SourceSearchScreenState extends ConsumerState<SourceSearchScreen> {
  String _query = '';
  final Set<String> _addingIds = {};

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(sourceSearchProvider(
      SourceSearchParams(sourceId: widget.sourceId, query: _query),
    ));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sourceName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search this source',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) => setState(() => _query = value),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        ),
      ),
      body: _query.isEmpty
          ? const Center(child: Text('Type to search this source.'))
          : resultsAsync.when(
              data: (results) {
                if (results.isEmpty) {
                  return const Center(child: Text('No results found.'));
                }
                return ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final manga = results[index];
                    return ListTile(
                      leading: SizedBox(
                        width: 40,
                        height: 56,
                        child: manga.coverUrl != null
                            ? AuthenticatedImage(
                                imageUrl: manga.coverUrl!,
                                headers: manga.coverHeaders,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                              ),
                      ),
                      title: Text(manga.title),
                      trailing: manga.inLibrary
                          ? const Icon(Icons.check_circle_outline)
                          : IconButton(
                              icon: _addingIds.contains(manga.id)
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.add_circle_outline),
                              tooltip: 'Add to library',
                              onPressed: _addingIds.contains(manga.id)
                                  ? null
                                  : () => _addToLibrary(manga),
                            ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Search failed: $error')),
            ),
    );
  }

  Future<void> _addToLibrary(KsSourceManga manga) async {
    final rawBackend = ref.read(activeBackendProvider);
    if (rawBackend is! SourceCapableBackend) return;
    final backend = rawBackend as SourceCapableBackend;

    setState(() => _addingIds.add(manga.id));
    try {
      await backend.addToLibrary(manga.id);
      ref.invalidate(sourceSearchProvider(
        SourceSearchParams(sourceId: widget.sourceId, query: _query),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "${manga.title}" to library')),
        );
      }
    } finally {
      if (mounted) setState(() => _addingIds.remove(manga.id));
    }
  }
}
