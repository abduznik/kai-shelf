import 'package:flutter/material.dart';

import '../../../../core/backend/models.dart';
import '../../domain/library_filter.dart';

String statusLabel(MangaStatus s) => switch (s) {
      MangaStatus.unknown => 'Unknown',
      MangaStatus.ongoing => 'Ongoing',
      MangaStatus.completed => 'Completed',
      MangaStatus.licensed => 'Licensed',
      MangaStatus.publishingFinished => 'Publishing finished',
      MangaStatus.cancelled => 'Cancelled',
      MangaStatus.onHiatus => 'On hiatus',
    };

/// Sort, status and genre options for the library grid. Genres cycle
/// through off → must have → must not have on tap.
class LibraryFilterSheet extends StatefulWidget {
  const LibraryFilterSheet(
      {super.key, required this.initial, required this.genres});

  final LibraryFilter initial;
  final List<String> genres;

  @override
  State<LibraryFilterSheet> createState() => _LibraryFilterSheetState();
}

class _LibraryFilterSheetState extends State<LibraryFilterSheet> {
  late LibraryFilter _filter = widget.initial;

  void _cycleGenre(String genre) {
    final inc = {..._filter.includeGenres};
    final exc = {..._filter.excludeGenres};
    if (inc.remove(genre)) {
      exc.add(genre);
    } else if (exc.remove(genre)) {
      // back to off
    } else {
      inc.add(genre);
    }
    setState(() => _filter = _filter.copyWith(
          includeGenres: inc,
          excludeGenres: exc,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Text('Sort & filter',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(
                      () => _filter = LibraryFilter(query: _filter.query)),
                  child: const Text('Reset'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _filter),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              children: [
                Text('Sort by', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in LibrarySort.values)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: _filter.sort == s,
                        onSelected: (_) =>
                            setState(() => _filter = _filter.copyWith(sort: s)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Status', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in MangaStatus.values)
                      FilterChip(
                        label: Text(statusLabel(s)),
                        selected: _filter.statuses.contains(s),
                        onSelected: (v) {
                          final next = {..._filter.statuses};
                          v ? next.add(s) : next.remove(s);
                          setState(
                              () => _filter = _filter.copyWith(statuses: next));
                        },
                      ),
                  ],
                ),
                if (widget.genres.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Genres (tap: include, again: exclude)',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final g in widget.genres)
                        FilterChip(
                          avatar: _filter.excludeGenres.contains(g)
                              ? const Icon(Icons.block, size: 16)
                              : null,
                          label: Text(g),
                          selected: _filter.includeGenres.contains(g),
                          onSelected: (_) => _cycleGenre(g),
                        ),
                    ],
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
