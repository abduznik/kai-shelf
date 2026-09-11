import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/source_providers.dart';

/// Lists installed Suwayomi sources (extensions) that can be searched to
/// discover manga not yet in the library. Only reachable when the active
/// backend supports source discovery — see sourceListProvider.
class SourceListScreen extends ConsumerWidget {
  const SourceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(sourceListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: sourcesAsync.when(
        data: (sources) {
          if (sources.isEmpty) {
            return const Center(
              child: Text('No sources available on this server.'),
            );
          }
          return ListView.builder(
            itemCount: sources.length,
            itemBuilder: (context, index) {
              final source = sources[index];
              return ListTile(
                title: Text(source.name),
                subtitle: source.lang != null ? Text(source.lang!) : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(
                    '/discover/${source.id}?name=${Uri.encodeComponent(source.name)}'),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Failed to load sources: $error')),
      ),
    );
  }
}
