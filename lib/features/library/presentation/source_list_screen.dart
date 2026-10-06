import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/models.dart';
import '../../../core/providers/source_providers.dart';
import '../domain/source_filter.dart';

/// Lists installed Suwayomi sources (extensions) that can be browsed or
/// searched to discover manga not yet in the library, with name, language
/// and content-rating filters plus a search across every source at once.
class SourceListScreen extends ConsumerStatefulWidget {
  const SourceListScreen({super.key});

  @override
  ConsumerState<SourceListScreen> createState() => _SourceListScreenState();
}

class _SourceListScreenState extends ConsumerState<SourceListScreen> {
  SourceListFilter _filter = const SourceListFilter();

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourceListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            icon: const Icon(Icons.travel_explore),
            tooltip: 'Search all sources',
            onPressed: () => context.push('/discover/all'),
          ),
          IconButton(
            icon: const Icon(Icons.extension_outlined),
            tooltip: 'Extensions',
            onPressed: () => context.push('/extensions'),
          ),
        ],
      ),
      body: sourcesAsync.when(
        data: (sources) {
          final usable = sources.where((s) => s.id != '0').toList();
          if (usable.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No sources installed on this server yet.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => context.push('/extensions'),
                      icon: const Icon(Icons.extension_outlined),
                      label: const Text('Install extensions'),
                    ),
                  ],
                ),
              ),
            );
          }
          final visible = _filter.apply(usable);
          final langs = SourceListFilter.languagesOf(usable);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Filter sources',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) =>
                      setState(() => _filter = _filter.copyWith(query: v)),
                ),
              ),
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
                        onSelected: (v) => setState(
                            () => _filter = _filter.copyWith(hideNsfw: v)),
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
              Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('No sources match.'))
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) =>
                            _tile(context, visible[index]),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Failed to load sources: $error')),
      ),
    );
  }

  Widget _tile(BuildContext context, KsSource source) {
    return ListTile(
      title: Text(source.name),
      subtitle: Text([
        if (source.lang != null) source.lang!.toUpperCase(),
        if (source.contentWarning == ContentWarning.nsfw) '18+',
        if (source.contentWarning == ContentWarning.mixed) 'Mixed content',
      ].join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(
          '/discover/${source.id}?name=${Uri.encodeComponent(source.label)}'),
    );
  }
}
