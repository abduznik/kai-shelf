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
        return [
          ListTile(
            dense: true,
            title: Text(filter.name),
            leading: Icon(switch (state) {
              KsTriState.include => Icons.check_box,
              KsTriState.exclude => Icons.indeterminate_check_box,
              KsTriState.ignore => Icons.check_box_outline_blank,
            }),
            onTap: () => _set(KsFilterChange(
              path: path,
              triState: KsTriState
                  .values[(state.index + 1) % KsTriState.values.length],
            )),
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
        // Counts non-default selections so a collapsed group still shows
        // that something inside it is active.
        final active =
            _changes.keys.where((k) => k.startsWith('${_key(path)}/')).length;
        return [
          ExpansionTile(
            title: Text(active == 0 ? filter.name : '${filter.name} ($active)'),
            dense: true,
            children: [
              for (final c in filter.children) ..._build(c, path),
            ],
          ),
        ];
    }
  }
}
