import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/models.dart';
import '../../../core/backend/server_backend.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/source_providers.dart';
import '../../../core/widgets/authenticated_image.dart';
import '../domain/source_filter.dart';

/// Searches every installed source at once and groups hits by source.
/// Sources are queried a few at a time and stream in as they answer, so
/// one slow or broken source can't block the rest.
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _SourceResult {
  _SourceResult(this.source);
  final KsSource source;
  List<KsSourceManga>? items;
  Object? error;
  bool get done => items != null || error != null;
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  static const _parallelism = 4;

  SourceListFilter _filter = const SourceListFilter(hideNsfw: true);
  List<_SourceResult> _results = [];
  String _query = '';
  int _generation = 0;
  bool _searched = false;

  Future<void> _search(String query, List<KsSource> sources) async {
    final backend = ref.read(activeBackendProvider);
    if (backend is! SourceCapableBackend || query.trim().isEmpty) return;
    final capable = backend as SourceCapableBackend;
    final gen = ++_generation;
    final targets = _filter.apply(sources.where((s) => s.id != '0').toList());
    final results = [for (final s in targets) _SourceResult(s)];
    setState(() {
      _query = query.trim();
      _results = results;
      _searched = true;
    });

    var next = 0;
    Future<void> worker() async {
      while (next < results.length) {
        final r = results[next++];
        try {
          final page = await capable.browseSource(r.source.id,
              mode: SourceBrowseMode.search, query: _query);
          r.items = page.items;
        } catch (e) {
          r.error = e;
        }
        if (!mounted || gen != _generation) return;
        setState(() {});
      }
    }

    await Future.wait([for (var i = 0; i < _parallelism; i++) worker()]);
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourceListProvider);
    final sources = sourcesAsync.valueOrNull ?? const <KsSource>[];
    final langs = SourceListFilter.languagesOf(sources);
    final shown = _results.where((r) => r.items?.isNotEmpty ?? !r.done);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search all sources'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Title to search for',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => _search(v, sources),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: const Text('Hide NSFW'),
                    selected: _filter.hideNsfw,
                    onSelected: (v) =>
                        setState(() => _filter = _filter.copyWith(hideNsfw: v)),
                  ),
                ),
                for (final lang in langs)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(lang.toUpperCase()),
                      selected: _filter.languages.contains(lang),
                      onSelected: (v) => setState(() {
                        final next = {..._filter.languages};
                        v ? next.add(lang) : next.remove(lang);
                        _filter = _filter.copyWith(languages: next);
                      }),
                    ),
                  ),
              ],
            ),
          ),
          if (_results.any((r) => !r.done)) const LinearProgressIndicator(),
          Expanded(
            child: !_searched
                ? const Center(
                    child: Text('Search every installed source at once.'))
                : ListView(
                    children: [
                      for (final r in shown) _section(context, r),
                      if (_results.every((r) => r.done) && shown.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('No results found.')),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, _SourceResult r) {
    final items = r.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          title: Text(r.source.label,
              style: Theme.of(context).textTheme.titleSmall),
          trailing: TextButton(
            onPressed: () => context.push(
                '/discover/${r.source.id}?name=${Uri.encodeComponent(r.source.label)}'),
            child: const Text('Open'),
          ),
        ),
        if (items == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          )
        else
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => InkWell(
                onTap: () => context.push('/manga/${items[i].id}'),
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: items[i].coverUrl == null
                              ? const ColoredBox(color: Colors.black12)
                              : AuthenticatedImage(
                                  imageUrl: items[i].coverUrl!,
                                  headers: items[i].coverHeaders,
                                  fit: BoxFit.cover,
                                  errorWidget: (c, e) => const ColoredBox(
                                      color: Colors.black12,
                                      child: Icon(Icons.broken_image_outlined)),
                                ),
                        ),
                      ),
                      Text(items[i].title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
