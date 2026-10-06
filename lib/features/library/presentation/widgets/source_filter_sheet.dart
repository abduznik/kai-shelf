import 'package:flutter/material.dart';

import '../../../../core/backend/models.dart';

String _key(List<int> path) => path.join('/');

/// Bottom sheet that renders a source's own filters (genres, status, sort,
/// free-text fields, ...) dynamically and returns the edits the user made.
/// Only changed filters are returned, so an untouched sheet sends nothing.
class SourceFilterSheet extends StatefulWidget {
  const SourceFilterSheet(
      {super.key, required this.filters, required this.initial});

  final List<KsSourceFilter> filters;
  final List<KsFilterChange> initial;

  @override
  State<SourceFilterSheet> createState() => _SourceFilterSheetState();
}

class _SourceFilterSheetState extends State<SourceFilterSheet> {
  late final Map<String, KsFilterChange> _changes = {
    for (final c in widget.initial) _key(c.path): c,
  };

  void _set(KsFilterChange change) =>
      setState(() => _changes[_key(change.path)] = change);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Text('Filters', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(_changes.clear),
                  child: const Text('Reset'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, _changes.values.toList()),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final f in widget.filters) ..._build(f, const []),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _build(KsSourceFilter filter, List<int> parent) {
    final path = [...parent, filter.position];
    final change = _changes[_key(path)];

    switch (filter) {
      case KsHeaderFilter():
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(filter.name,
                style: Theme.of(context).textTheme.labelLarge),
          ),
        ];
      case KsSeparatorFilter():
        return [const Divider()];
      case KsTextFilter():
        return [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextFormField(
              initialValue: change?.text ?? filter.value,
              decoration: InputDecoration(
                labelText: filter.name,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => _set(KsFilterChange(path: path, text: v)),
            ),
          ),
        ];
      case KsCheckBoxFilter():
        return [
          CheckboxListTile(
            dense: true,
            title: Text(filter.name),
            value: change?.checkBox ?? filter.value,
            onChanged: (v) =>
                _set(KsFilterChange(path: path, checkBox: v ?? false)),
          ),
        ];
      case KsTriStateFilter():
        final state = change?.triState ?? filter.value;
        final scheme = Theme.of(context).colorScheme;
        // Both choices are always visible: many tag lists let you require
        // a tag as well as hide it, and a tap-to-cycle row hides that.
        return [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    filter.name,
                    style: TextStyle(
                      color: switch (state) {
                        KsTriState.include => Colors.green,
                        KsTriState.exclude => scheme.error,
                        KsTriState.ignore => null,
                      },
                      fontWeight: state == KsTriState.ignore
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                ),
                SegmentedButton<KsTriState>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  segments: const [
                    ButtonSegment(
                        value: KsTriState.ignore,
                        icon: Icon(Icons.remove, size: 16),
                        tooltip: 'Any'),
                    ButtonSegment(
                        value: KsTriState.include,
                        icon: Icon(Icons.add, size: 16),
                        tooltip: 'Include'),
                    ButtonSegment(
                        value: KsTriState.exclude,
                        icon: Icon(Icons.block, size: 16),
                        tooltip: 'Exclude'),
                  ],
                  selected: {state},
                  onSelectionChanged: (v) =>
                      _set(KsFilterChange(path: path, triState: v.first)),
                ),
              ],
            ),
          ),
        ];
      case KsSelectFilter():
        final selected = change?.select ?? filter.selected;
        return [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: DropdownButtonFormField<int>(
              initialValue: selected.clamp(0, filter.options.length - 1),
              isExpanded: true,
              decoration: InputDecoration(
                labelText: filter.name,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (var i = 0; i < filter.options.length; i++)
                  DropdownMenuItem(value: i, child: Text(filter.options[i])),
              ],
              onChanged: (v) =>
                  _set(KsFilterChange(path: path, select: v ?? 0)),
            ),
          ),
        ];
      case KsSortFilter():
        final index = change?.sortIndex ?? filter.selected;
        final ascending = change?.sortAscending ?? filter.ascending;
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: index.clamp(0, filter.options.length - 1),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: filter.name,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (var i = 0; i < filter.options.length; i++)
                        DropdownMenuItem(
                            value: i, child: Text(filter.options[i])),
                    ],
                    onChanged: (v) => _set(KsFilterChange(
                        path: path,
                        sortIndex: v ?? 0,
                        sortAscending: ascending)),
                  ),
                ),
                IconButton(
                  tooltip: ascending ? 'Ascending' : 'Descending',
                  icon: Icon(
                      ascending ? Icons.arrow_upward : Icons.arrow_downward),
                  onPressed: () => _set(KsFilterChange(
                      path: path, sortIndex: index, sortAscending: !ascending)),
                ),
              ],
            ),
          ),
        ];
      case KsGroupFilter():
        // Summarises what's set inside, so a collapsed group still shows
        // that something in it is active.
        var included = 0, excluded = 0, other = 0;
        for (final entry in _changes.entries) {
          if (!entry.key.startsWith('${_key(path)}/')) continue;
          switch (entry.value.triState) {
            case KsTriState.include:
              included++;
            case KsTriState.exclude:
              excluded++;
            case KsTriState.ignore:
              break;
            case null:
              other++;
          }
        }
        final summary = [
          if (included > 0) '+$included',
          if (excluded > 0) '−$excluded',
          if (other > 0) '$other set',
        ].join(' ');
        return [
          ExpansionTile(
            title: Text(
                summary.isEmpty ? filter.name : '${filter.name} ($summary)'),
            dense: true,
            children: [
              for (final c in filter.children) ..._build(c, path),
            ],
          ),
        ];
    }
  }
}
