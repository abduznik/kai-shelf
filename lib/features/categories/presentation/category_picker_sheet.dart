import 'package:flutter/material.dart';

import '../../../core/backend/models.dart';
import '../../../core/backend/server_backend.dart';

/// What the user chose in [CategoryPickerSheet].
class CategoryPick {
  const CategoryPick.save(this.categoryIds) : removeFromLibrary = false;
  const CategoryPick.remove()
      : categoryIds = const {},
        removeFromLibrary = true;

  final Set<String> categoryIds;
  final bool removeFromLibrary;
}

enum CategoryOutcome { cancelled, added, updated, removed }

/// Bottom sheet that lets the user tick any number of named categories for one
/// manga, create a new one inline, or drop the manga from the library.
class CategoryPickerSheet extends StatefulWidget {
  const CategoryPickerSheet({
    super.key,
    required this.backend,
    required this.mangaId,
    required this.inLibrary,
    required this.canRemove,
  });

  final CategoryCapableBackend backend;
  final String mangaId;
  final bool inLibrary;

  /// Whether the server lets the manga leave the library at all (Suwayomi).
  final bool canRemove;

  @override
  State<CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<CategoryPickerSheet> {
  List<KsCategory>? _categories;
  final Set<String> _selected = {};
  Object? _error;

  CategoryCapableBackend get _backend => widget.backend;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final categories = await _backend.getCategories();
      final current = widget.inLibrary
          ? await _backend.getMangaCategoryIds(widget.mangaId)
          : <String>{};
      if (!mounted) return;
      setState(() {
        // The built-in default category means "no category", so it is not
        // something to tick.
        _categories = categories.where((c) => !c.isDefault).toList();
        _selected.addAll(current);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _createNew() async {
    final name = await askCategoryName(
      context,
      title: 'New ${_backend.categoryNoun}',
      confirmLabel: 'Create',
    );
    if (name == null || !mounted) return;
    try {
      // Komga refuses an empty collection, so the new one starts with this
      // manga already in it.
      final created = await _backend.createCategory(name,
          firstMangaId:
              _backend.canCreateEmptyCategory ? null : widget.mangaId);
      if (!mounted) return;
      setState(() {
        _categories = [...?_categories, created];
        _selected.add(created.id);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final noun = _backend.categoryNoun;
    final categories = _categories;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              widget.inLibrary
                  ? 'Edit ${_backend.categoryNounPlural}'
                  : 'Add to library',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  'Failed to load ${_backend.categoryNounPlural}: $_error'),
            )
          else if (categories == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final category in categories)
                    CheckboxListTile(
                      value: _selected.contains(category.id),
                      title: Text(category.name),
                      onChanged: (checked) => setState(() => checked == true
                          ? _selected.add(category.id)
                          : _selected.remove(category.id)),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: Text('New $noun'),
                    onTap: _createNew,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                if (widget.inLibrary && widget.canRemove)
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, const CategoryPick.remove()),
                    child: const Text('Remove from library'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: categories == null
                      ? null
                      : () => Navigator.pop(
                          context, CategoryPick.save(Set.of(_selected))),
                  child: Text(widget.inLibrary ? 'Save' : 'Add to library'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog(
      {required this.title, required this.confirmLabel, this.initial = ''});

  final String title;
  final String confirmLabel;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// Asks for a category name; null when cancelled. Shared with the
/// management screen so both use the same dialog.
Future<String?> askCategoryName(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _NameDialog(title: title, confirmLabel: confirmLabel, initial: initial),
  );
}
