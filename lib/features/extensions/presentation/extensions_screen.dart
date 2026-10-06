import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/extension_providers.dart';
import '../../../core/backend/server_backend.dart';
import '../../../core/widgets/authenticated_image.dart';
import 'extension_filter.dart';

/// Install, update and remove source extensions, and manage the
/// repositories they come from.
class ExtensionsScreen extends ConsumerStatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  ConsumerState<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends ConsumerState<ExtensionsScreen> {
  ExtensionFilter _filter = const ExtensionFilter();
  final Set<String> _busy = {};

  Future<void> _run(String pkg, Future<void> Function() op) async {
    setState(() => _busy.add(pkg));
    try {
      await op();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(pkg));
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(activeBackendProvider);
    if (backend is! ExtensionCapableBackend) {
      return Scaffold(
        appBar: AppBar(title: const Text('Extensions')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
                'Extensions are only available on Suwayomi servers. Komga and '
                'Kavita index files already on the server.'),
          ),
        ),
      );
    }

    final extensionsAsync = ref.watch(extensionsProvider);
    final notifier = ref.read(extensionsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
        actions: [
          if (extensionsAsync.valueOrNull?.any((e) => e.hasUpdate) ?? false)
            TextButton(
              onPressed: () => _updateAll(extensionsAsync.value!),
              child: const Text('Update all'),
            ),
          IconButton(
            icon: const Icon(Icons.source_outlined),
            tooltip: 'Repositories',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const _ReposSheet(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh from repositories',
            onPressed: () => notifier.refresh(),
          ),
        ],
      ),
      body: extensionsAsync.when(
        data: (all) => _buildList(context, all),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load extensions: $e')),
      ),
    );
  }

  Future<void> _updateAll(List<KsExtension> all) async {
    final notifier = ref.read(extensionsProvider.notifier);
    for (final e in all.where((e) => e.hasUpdate)) {
      await _run(e.pkgName, () => notifier.upgrade(e.pkgName));
    }
  }

  Widget _buildList(BuildContext context, List<KsExtension> all) {
    if (all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'No extensions yet. Add a repository, then refresh to load '
                  'its extensions.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const _ReposSheet(),
                ),
                child: const Text('Manage repositories'),
              ),
            ],
          ),
        ),
      );
    }

    final visible = _filter.apply(all);
    final langs = ExtensionFilter.languagesOf(all);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search extensions',
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
              for (final status in ExtensionStatus.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(status.label),
                    selected: _filter.status == status,
                    onSelected: (_) => setState(
                        () => _filter = _filter.copyWith(status: status)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  label: const Text('Hide NSFW'),
                  selected: _filter.hideNsfw,
                  onSelected: (v) =>
                      setState(() => _filter = _filter.copyWith(hideNsfw: v)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ActionChip(
                  avatar: const Icon(Icons.language, size: 18),
                  label: Text(_filter.languages.isEmpty
                      ? 'All languages'
                      : _filter.languages.join(', ')),
                  onPressed: () => _pickLanguages(langs),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(extensionsProvider.notifier).refresh(),
            child: visible.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 120),
                    Center(child: Text('No extensions match.')),
                  ])
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) => _tile(visible[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _tile(KsExtension e) {
    final notifier = ref.read(extensionsProvider.notifier);
    final busy = _busy.contains(e.pkgName);
    final info = [
      if (e.lang != null) e.lang!.toUpperCase(),
      if (e.versionName != null) 'v${e.versionName}',
      if (e.contentWarning == ContentWarning.nsfw) '18+',
      if (e.contentWarning == ContentWarning.mixed) 'Mixed content',
      if (e.storeName != null) e.storeName!,
    ].join(' · ');

    Widget action;
    if (busy) {
      action = const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2));
    } else if (e.hasUpdate) {
      action = FilledButton(
        onPressed: () => _run(e.pkgName, () => notifier.upgrade(e.pkgName)),
        child: const Text('Update'),
      );
    } else if (e.isInstalled) {
      action = OutlinedButton(
        onPressed: () => _run(e.pkgName, () => notifier.uninstall(e.pkgName)),
        child: const Text('Uninstall'),
      );
    } else {
      action = FilledButton.tonal(
        onPressed: () => _run(e.pkgName, () => notifier.install(e.pkgName)),
        child: const Text('Install'),
      );
    }

    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 40,
        child: e.iconUrl == null
            ? const Icon(Icons.extension_outlined)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AuthenticatedImage(
                  imageUrl: e.iconUrl!,
                  headers: ref.read(activeConnectionProvider)?.extraHeaders,
                  fit: BoxFit.cover,
                  errorWidget: (context, error) =>
                      const Icon(Icons.extension_outlined),
                ),
              ),
      ),
      title: Text(e.name),
      subtitle: Text(info),
      trailing: action,
    );
  }

  Future<void> _pickLanguages(List<String> langs) async {
    final selected = {..._filter.languages};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Languages'),
          content: SizedBox(
            width: 320,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final l in langs)
                  CheckboxListTile(
                    dense: true,
                    title: Text(l),
                    value: selected.contains(l),
                    onChanged: (v) => setLocal(
                        () => v == true ? selected.add(l) : selected.remove(l)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, <String>{}),
                child: const Text('Clear')),
            FilledButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() => _filter = _filter.copyWith(languages: result));
    }
  }
}

class _ReposSheet extends ConsumerStatefulWidget {
  const _ReposSheet();

  @override
  ConsumerState<_ReposSheet> createState() => _ReposSheetState();
}

class _ReposSheetState extends ConsumerState<_ReposSheet> {
  static const keiyoushi =
      'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json';
  final _controller = TextEditingController();
  String? _error;
  bool _working = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ExtensionCapableBackend get _backend =>
      ref.read(activeBackendProvider)! as ExtensionCapableBackend;

  Future<void> _add(String url) async {
    url = url.trim();
    if (!url.startsWith('http')) {
      setState(() => _error = 'Enter a full http(s) index URL.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _backend.addExtensionRepo(url);
      _controller.clear();
      ref.invalidate(extensionReposProvider);
      await ref.read(extensionsProvider.notifier).refresh();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _remove(String url) async {
    setState(() => _working = true);
    try {
      await _backend.removeExtensionRepo(url);
      ref.invalidate(extensionReposProvider);
      await ref.read(extensionsProvider.notifier).refresh();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reposAsync = ref.watch(extensionReposProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Repositories', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_working) const LinearProgressIndicator(),
          reposAsync.when(
            data: (repos) => Column(
              children: [
                if (repos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No repositories added yet.'),
                  ),
                for (final r in repos)
                  ListTile(
                    dense: true,
                    title: Text(r.name),
                    subtitle: Text(r.indexUrl,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: _working ? null : () => _remove(r.indexUrl),
                    ),
                  ),
              ],
            ),
            loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('Failed to load repositories: $e'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: 'Repository index URL',
              errorText: _error,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add repository',
                onPressed: _working ? null : () => _add(_controller.text),
              ),
            ),
            onSubmitted: _add,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _working ? null : () => _add(keiyoushi),
            icon: const Icon(Icons.bolt),
            label: const Text('Add Keiyoushi (community default)'),
          ),
        ],
      ),
    );
  }
}
