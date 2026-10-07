import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/models.dart';
import '../../../core/backend/server_backend.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/category_providers.dart';
import 'category_picker_sheet.dart';

/// Create, rename, reorder and delete the server's named categories
/// (Suwayomi categories, Komga/Kavita collections). Tapping one opens the
/// manga inside it.
class CategoryManageScreen extends ConsumerStatefulWidget {
  const CategoryManageScreen({super.key});

  @override
  ConsumerState<CategoryManageScreen> createState() =>
      _CategoryManageScreenState();
}

class _CategoryManageScreenState extends ConsumerState<CategoryManageScreen> {
  /// Shown while a reorder request is in flight, so the row does not snap
  /// back to its old place until the server answers.
  List<KsCategory>? _pendingOrder;

  CategoryCapableBackend? get _backend {
    final backend = ref.read(activeBackendProvider);
    return backend is CategoryCapableBackend
        ? backend as CategoryCapableBackend
        : null;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _pendingOrder = null);
        invalidateCategoryData(ref);
      }
    }
  }

  Future<void> _create() async {
    final backend = _backend!;
    final name = await askCategoryName(context,
        title: 'New ${backend.categoryNoun}', confirmLabel: 'Create');
    if (name == null) return;
    await _run(() => backend.createCategory(name));
  }

  Future<void> _rename(KsCategory category) async {
    final backend = _backend!;
    final name = await askCategoryName(context,
        title: 'Rename ${backend.categoryNoun}',
        confirmLabel: 'Rename',
        initial: category.name);
    if (name == null || name == category.name) return;
    await _run(() => backend.renameCategory(category.id, name));
  }

  Future<void> _delete(KsCategory category) async {
    final backend = _backend!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${category.name}"?'),
        content: Text('The manga stay on the server; only this '
            '${backend.categoryNoun} is removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => backend.deleteCategory(category.id));
  }

  Future<void> _reorder(
      List<KsCategory> editable, int oldIndex, int newIndex) async {
    if (newIndex == oldIndex) return;
    final moved = [...editable];
    final item = moved.removeAt(oldIndex);
    moved.insert(newIndex, item);
    setState(() => _pendingOrder = moved);
    await _run(() => _backend!.moveCategory(item.id, newIndex));
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(activeBackendProvider);
    if (backend is! CategoryCapableBackend) {
      return Scaffold(
        appBar: AppBar(title: const Text('Categories')),
        body: const Center(
            child: Text('This server does not support categories.')),
      );
    }
    final caps = backend as CategoryCapableBackend;
    final noun = caps.categoryNoun;
    final plural = caps.categoryNounPlural;
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(caps.categoryTitlePlural)),
      floatingActionButton: caps.canCreateEmptyCategory
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: Text('New $noun'),
            )
          : null,
      body: categoriesAsync.when(
        data: (all) {
          final defaults = all.where((c) => c.isDefault).toList();
          final editable =
              _pendingOrder ?? all.where((c) => !c.isDefault).toList();
          if (editable.isEmpty && defaults.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  caps.canCreateEmptyCategory
                      ? 'No $plural yet.'
                      : 'No $plural yet. Create one from a manga: its '
                          'page has a $noun button, and a $noun needs at '
                          'least one manga.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(
            children: [
              for (final category in defaults)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(category.name),
                  subtitle: Text('Manga without a $noun '
                      '(${category.mangaCount})'),
                  onTap: () => _open(category),
                ),
              Expanded(
                child: caps.canReorderCategories
                    ? ReorderableListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: editable.length,
                        buildDefaultDragHandles: false,
                        onReorderItem: (o, n) => _reorder(editable, o, n),
                        itemBuilder: (context, i) => _tile(editable[i],
                            key: ValueKey(editable[i].id), index: i),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: editable.length,
                        itemBuilder: (context, i) =>
                            _tile(editable[i], key: ValueKey(editable[i].id)),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
      ),
    );
  }

  void _open(KsCategory category) => context.push(
      '/categories/${category.id}?name=${Uri.encodeQueryComponent(category.name)}');

  Widget _tile(KsCategory category, {required Key key, int? index}) {
    final menu = PopupMenuButton<String>(
      tooltip: 'Options for ${category.name}',
      onSelected: (value) =>
          value == 'rename' ? _rename(category) : _delete(category),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    return ListTile(
      key: key,
      leading: const Icon(Icons.label_outline),
      title: Text(category.name),
      subtitle: Text('${category.mangaCount} manga'),
      onTap: () => _open(category),
      // An explicit handle, since the default long-press drag is invisible
      // and unreliable with a mouse.
      trailing: index == null
          ? menu
          : Row(mainAxisSize: MainAxisSize.min, children: [
              menu,
              ReorderableDragStartListener(
                index: index,
                child: Tooltip(
                  message: 'Drag to reorder',
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
              ),
            ]),
    );
  }
}
