import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/models.dart';
import '../../../core/backend/server_backend.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/history_providers.dart';
import '../../../core/widgets/authenticated_image.dart';
import '../../../core/widgets/incognito_badge.dart';
import '../domain/history_logic.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key, this.now});

  /// Injected by tests so "Today"/"Yesterday" are deterministic.
  final DateTime? now;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  GoRouter? _router;
  String? _ownPath;
  bool _away = false;

  /// Refetches when the user comes back to this screen after reading
  /// elsewhere. Done off the router's location rather than the awaited
  /// push result or autoDispose: in the web build, coming back via the
  /// browser's back button left a stale list. The last match's location is
  /// used because a pushed route does not change the delegate's uri.
  void _onLocationChanged() {
    final path =
        _router!.routerDelegate.currentConfiguration.last.matchedLocation;
    if (path != _ownPath) {
      _away = true;
    } else if (_away) {
      _away = false;
      ref.invalidate(historyProvider);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (router == _router) return;
    _router?.routerDelegate.removeListener(_onLocationChanged);
    _router = router;
    // The screen is built at its own location, so "now" is its own path.
    _ownPath = router?.routerDelegate.currentConfiguration.last.matchedLocation;
    router?.routerDelegate.addListener(_onLocationChanged);
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onLocationChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(activeBackendProvider);
    final historyAsync = ref.watch(historyProvider);
    final hasEntries = historyAsync.valueOrNull?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          const IncognitoBadge(),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear history',
            onPressed: hasEntries ? () => _confirmClear(context) : null,
          ),
        ],
      ),
      body: backend == null
          ? _Message(
              icon: Icons.dns_outlined,
              text: 'Connect to a server to see your reading history.',
              action: FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Connect')),
            )
          : backend is! HistoryCapableBackend
              ? const _Message(
                  icon: Icons.history,
                  text: 'This server does not provide reading history.')
              : historyAsync.when(
                  data: (entries) => entries.isEmpty
                      ? const _Message(
                          icon: Icons.history,
                          text: 'Nothing read yet. Chapters you open '
                              'will show up here.')
                      : RefreshIndicator(
                          onRefresh: () async =>
                              ref.refresh(historyProvider.future),
                          child: _HistoryList(
                              entries: entries,
                              now: widget.now ?? DateTime.now()),
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _Message(
                    icon: Icons.error_outline,
                    text: 'Failed to load history: $error',
                    action: FilledButton(
                        onPressed: () => ref.invalidate(historyProvider),
                        child: const Text('Retry')),
                  ),
                ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content:
            const Text('This hides all current entries on this device. Reading '
                'progress on the server is not changed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(historyProvider.notifier).clearAll();
    }
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.entries, required this.now});

  final List<KsHistoryEntry> entries;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = groupHistoryByDay(entries);
    return ListView(
      // Keeps pull-to-refresh working when the list is shorter than the view.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              dayLabel(day.day, now),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          for (final entry in day.entries)
            _HistoryTile(key: ValueKey(entry.chapterId), entry: entry),
        ],
      ],
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({super.key, required this.entry});

  final KsHistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle = '${entry.chapterTitle}\n${progressLabel(entry)}';
    return ListTile(
      isThreeLine: true,
      leading: SizedBox(
        width: 44,
        height: 64,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: entry.coverUrl == null
              ? const ColoredBox(
                  color: Colors.black12, child: Icon(Icons.menu_book))
              : AuthenticatedImage(
                  imageUrl: entry.coverUrl!,
                  headers: entry.coverHeaders,
                  fit: BoxFit.cover,
                  errorWidget: (context, error) => const ColoredBox(
                      color: Colors.black12, child: Icon(Icons.menu_book)),
                ),
        ),
      ),
      title:
          Text(entry.mangaTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<_RowAction>(
        tooltip: 'More',
        onSelected: (action) async {
          switch (action) {
            case _RowAction.openManga:
              await context.push('/manga/${entry.mangaId}');
            case _RowAction.remove:
              await ref.read(historyProvider.notifier).remove(entry);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: _RowAction.openManga, child: Text('Open manga')),
          PopupMenuItem(
              value: _RowAction.remove, child: Text('Remove from history')),
        ],
      ),
      // Resume: the reader picks up at the saved page by itself.
      onTap: () async {
        // Fresh progress is picked up when the screen is revisited.
        await context.push('/reader/${entry.mangaId}/${entry.chapterId}');
      },
    );
  }
}

enum _RowAction { openManga, remove }

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
