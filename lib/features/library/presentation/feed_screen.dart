import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/models.dart';
import '../../../core/backend/server_backend.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/feed_providers.dart';
import '../../../core/providers/source_providers.dart';
import '../../../core/widgets/authenticated_image.dart';
import '../domain/source_filter.dart';
import '../domain/source_listing.dart';

/// Latest releases from several sources at once, one horizontal row per
/// source. Which sources appear is the user's choice and is remembered.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  /// Without a saved choice, show only a few sources so opening the Feed
  /// never fans out to dozens of installed extensions.
  static const defaultSourceCount = 3;

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final Map<String, SourceListing> _listings = {};
  int _generation = 0;

  void _load(List<SourceListing> targets) {
    final backend = ref.read(activeBackendProvider);
    if (backend is! SourceCapableBackend || targets.isEmpty) return;
    final gen = _generation;
    loadSourceListings(
      backend as SourceCapableBackend,
      targets,
      mode: SourceBrowseMode.latest,
      cancelled: () => !mounted || gen != _generation,
      onProgress: () => setState(() {}),
    );
  }

  void _refresh() {
    _generation++;
    setState(_listings.clear);
  }

  List<KsSource> _selected(List<KsSource> usable, Set<String>? stored) {
    final ordered = SourceListFilter(hideNsfw: stored == null).apply(usable);
    if (stored == null) {
      return ordered
          .where((s) => s.supportsLatest)
          .take(FeedScreen.defaultSourceCount)
          .toList();
    }
    return ordered.where((s) => stored.contains(s.id)).toList();
  }

  Future<void> _choose(List<KsSource> usable, List<KsSource> current) async {
    final chosen = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SourcePickerSheet(
        sources: SourceListFilter().apply(usable),
        initial: {for (final s in current) s.id},
      ),
    );
    if (chosen != null) {
      await ref.read(feedSourcesProvider.notifier).set(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourceListProvider);
    final stored = ref.watch(feedSourcesProvider);
    final usable = [
      for (final s in sourcesAsync.valueOrNull ?? const <KsSource>[])
        if (s.id != '0') s
    ];
    final ready = sourcesAsync.hasValue && stored.hasValue;
    final selected =
        ready ? _selected(usable, stored.valueOrNull) : const <KsSource>[];

    final missing = [
      for (final s in selected)
        if (!_listings.containsKey(s.id)) SourceListing(s)
    ];
    if (missing.isNotEmpty) {
      for (final l in missing) {
        _listings[l.source.id] = l;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(missing));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Choose sources',
            onPressed: ready ? () => _choose(usable, selected) : null,
          ),
        ],
      ),
      body: !ready
          ? (sourcesAsync.hasError
              ? Center(
                  child: Text('Failed to load sources: ${sourcesAsync.error}'))
              : const Center(child: CircularProgressIndicator()))
          : selected.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No sources selected for the feed.'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: usable.isEmpty
                              ? null
                              : () => _choose(usable, selected),
                          child: const Text('Choose sources'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  children: [
                    for (final s in selected)
                      if (_listings[s.id] case final l?) _row(context, l),
                  ],
                ),
    );
  }

  Widget _row(BuildContext context, SourceListing l) {
    final items = l.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          title: Text(l.source.label,
              style: Theme.of(context).textTheme.titleSmall),
          trailing: TextButton(
            onPressed: () => context.push(
                '/discover/${l.source.id}?name=${Uri.encodeComponent(l.source.label)}'),
            child: const Text('Open'),
          ),
        ),
        if (l.error != null)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('Could not load this source.'),
          )
        else if (items == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          )
        else if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('Nothing new.'),
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

class _SourcePickerSheet extends StatefulWidget {
  const _SourcePickerSheet({required this.sources, required this.initial});

  final List<KsSource> sources;
  final Set<String> initial;

  @override
  State<_SourcePickerSheet> createState() => _SourcePickerSheetState();
}

class _SourcePickerSheetState extends State<_SourcePickerSheet> {
  late final Set<String> _chosen = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Sources in feed',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _chosen),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final s in widget.sources)
                  CheckboxListTile(
                    value: _chosen.contains(s.id),
                    title: Text(s.name),
                    subtitle: Text([
                      if (s.lang != null) s.lang!.toUpperCase(),
                      if (s.contentWarning == ContentWarning.nsfw) '18+',
                      if (!s.supportsLatest) 'No latest listing',
                    ].join(' · ')),
                    onChanged: (v) => setState(() =>
                        v == true ? _chosen.add(s.id) : _chosen.remove(s.id)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
