import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/models.dart';
import '../../../core/backend/server_backend.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/library_providers.dart';
import '../../../core/providers/source_providers.dart';
import '../../../core/widgets/authenticated_image.dart';
import '../../categories/presentation/category_actions.dart';
import '../../categories/presentation/category_picker_sheet.dart';
import 'widgets/source_filter_sheet.dart';

/// Browses one source: popular and latest listings, or a search narrowed
/// by the source's own filters. Results page in as the user scrolls and
/// each can be added to (or removed from) the library.
class SourceSearchScreen extends ConsumerStatefulWidget {
  const SourceSearchScreen(
      {super.key, required this.sourceId, required this.sourceName});

  final String sourceId;
  final String sourceName;

  @override
  ConsumerState<SourceSearchScreen> createState() => _SourceSearchScreenState();
}

class _SourceSearchScreenState extends ConsumerState<SourceSearchScreen> {
  final _scroll = ScrollController();
  final _searchController = TextEditingController();

  SourceBrowseMode _mode = SourceBrowseMode.popular;
  String _query = '';
  List<KsFilterChange> _filters = const [];

  final List<KsSourceManga> _items = [];
  final Set<String> _seen = {};
  final Set<String> _busyIds = {};
  int _page = 0;
  bool _hasNext = true;
  bool _loading = false;
  Object? _error;
  // Guards against a slow earlier request overwriting a newer one.
  int _generation = 0;

  SourceCapableBackend? get _backend {
    final b = ref.read(activeBackendProvider);
    return b is SourceCapableBackend ? b as SourceCapableBackend : null;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _generation++;
    setState(() {
      _items.clear();
      _seen.clear();
      _page = 0;
      _hasNext = true;
      _error = null;
      _loading = false;
    });
    _loadMore();
  }

  Future<void> _loadMore() async {
    final backend = _backend;
    if (backend == null || _loading || !_hasNext) return;
    final gen = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await backend.browseSource(
        widget.sourceId,
        mode: _mode,
        query: _query,
        page: _page + 1,
        filters: _filters,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _page++;
        _hasNext = result.hasNextPage;
        for (final m in result.items) {
          if (_seen.add(m.id)) _items.add(m);
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _submitSearch(String value) {
    _query = value.trim();
    _mode = _query.isEmpty && _filters.isEmpty
        ? SourceBrowseMode.popular
        : SourceBrowseMode.search;
    _reload();
  }

  Future<void> _openFilters() async {
    final filters =
        await ref.read(sourceFiltersProvider(widget.sourceId).future);
    if (!mounted) return;
    final result = await showModalBottomSheet<List<KsFilterChange>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SourceFilterSheet(filters: filters, initial: _filters),
    );
    if (result == null) return;
    _filters = result;
    _mode = _query.isEmpty && _filters.isEmpty
        ? SourceBrowseMode.popular
        : SourceBrowseMode.search;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final filtersAsync = ref.watch(sourceFiltersProvider(widget.sourceId));
    final hasFilters = filtersAsync.valueOrNull?.isNotEmpty ?? false;
    final sources = ref.watch(sourceListProvider).valueOrNull;
    final supportsLatest = sources
            ?.where((s) => s.id == widget.sourceId)
            .map((s) => s.supportsLatest)
            .firstOrNull ??
        true;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sourceName),
        actions: [
          if (hasFilters)
            IconButton(
              tooltip: 'Filters',
              icon: Badge(
                isLabelVisible: _filters.isNotEmpty,
                label: Text('${_filters.length}'),
                child: const Icon(Icons.filter_list),
              ),
              onPressed: _openFilters,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search this source',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _submitSearch('');
                            },
                          ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: _submitSearch,
                ),
              ),
              SegmentedButton<SourceBrowseMode>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(
                      value: SourceBrowseMode.popular, label: Text('Popular')),
                  if (supportsLatest)
                    const ButtonSegment(
                        value: SourceBrowseMode.latest, label: Text('Latest')),
                  const ButtonSegment(
                      value: SourceBrowseMode.search, label: Text('Search')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) {
                  _mode = s.first;
                  _reload();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_items.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Failed to load: $_error'),
              const SizedBox(height: 8),
              FilledButton(onPressed: _reload, child: const Text('Retry')),
            ],
          ),
        );
      }
      return const Center(child: Text('No results found.'));
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.58,
      ),
      itemCount: _items.length + (_hasNext || _error != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return _error != null
              ? Center(
                  child: TextButton(
                      onPressed: _loadMore, child: const Text('Retry')))
              : const Center(child: CircularProgressIndicator());
        }
        return _tile(_items[index]);
      },
    );
  }

  Widget _tile(KsSourceManga manga) {
    final busy = _busyIds.contains(manga.id);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _openManga(manga),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: manga.coverUrl != null
                      ? AuthenticatedImage(
                          imageUrl: manga.coverUrl!,
                          headers: manga.coverHeaders,
                          fit: BoxFit.cover,
                          errorWidget: (context, error) => Container(
                              color: scheme.surfaceContainerHighest,
                              child: const Icon(Icons.broken_image_outlined)),
                        )
                      : Container(color: scheme.surfaceContainerHighest),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    tooltip: manga.inLibrary
                        ? 'Remove from library'
                        : 'Add to library',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.surface.withValues(alpha: 0.9),
                    ),
                    onPressed: busy ? null : () => _toggleLibrary(manga),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(
                            manga.inLibrary
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 18,
                            color: manga.inLibrary
                                ? scheme.primary
                                : scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(manga.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  /// Opens the title so it can be read before deciding to add it. On
  /// return, picks up a library change made from the detail screen.
  Future<void> _openManga(KsSourceManga manga) async {
    await context.push('/manga/${manga.id}');
    if (!mounted) return;
    final raw = ref.read(activeBackendProvider);
    if (raw == null) return;
    try {
      final detail = await raw.getMangaDetail(manga.id);
      final index = _items.indexWhere((m) => m.id == manga.id);
      if (index != -1 &&
          mounted &&
          _items[index].inLibrary != detail.inLibrary) {
        setState(() =>
            _items[index] = _withLibrary(_items[index], detail.inLibrary));
      }
    } catch (_) {
      // Not worth interrupting browsing over.
    }
  }

  KsSourceManga _withLibrary(KsSourceManga m, bool inLibrary) => KsSourceManga(
        id: m.id,
        title: m.title,
        coverUrl: m.coverUrl,
        coverHeaders: m.coverHeaders,
        description: m.description,
        genres: m.genres,
        inLibrary: inLibrary,
      );

  Future<void> _toggleLibrary(KsSourceManga manga) async {
    final backend = _backend;
    if (backend == null) return;
    // Servers with named categories let the user pick them while adding;
    // picking none still adds to the default one.
    final categoryBackend = ref.read(activeBackendProvider);
    var nowInLibrary = !manga.inLibrary;
    if (categoryBackend is CategoryCapableBackend) {
      final CategoryOutcome outcome;
      try {
        outcome = await pickAndApplyCategories(context,
            backend: categoryBackend,
            mangaId: manga.id,
            inLibrary: manga.inLibrary);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
        return;
      }
      if (outcome == CategoryOutcome.cancelled) return;
      nowInLibrary = outcome != CategoryOutcome.removed;
      ref.invalidate(libraryListProvider);
      ref.invalidate(mangaListProvider);
    }
    setState(() => _busyIds.add(manga.id));
    try {
      if (categoryBackend is! CategoryCapableBackend) {
        if (manga.inLibrary) {
          await backend.removeFromLibrary(manga.id);
        } else {
          await backend.addToLibrary(manga.id);
        }
      }
      final index = _items.indexWhere((m) => m.id == manga.id);
      if (index != -1 && mounted) {
        setState(() => _items[index] = _withLibrary(manga, nowInLibrary));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(nowInLibrary
              ? (manga.inLibrary
                  ? 'Updated "${manga.title}"'
                  : 'Added "${manga.title}" to library')
              : 'Removed "${manga.title}" from library'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(manga.id));
    }
  }
}
