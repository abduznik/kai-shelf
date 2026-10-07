import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/server_backend.dart';
import '../../../core/providers/backend_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(activeBackendProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (backend is SourceCapableBackend)
            ListTile(
              leading: const Icon(Icons.explore_outlined),
              title: const Text('Sources'),
              subtitle:
                  const Text('Browse, filter and search installed sources'),
              onTap: () => context.push('/discover'),
            ),
          if (backend is CategoryCapableBackend)
            ListTile(
              leading: const Icon(Icons.label_outline),
              title:
                  Text((backend as CategoryCapableBackend).categoryTitlePlural),
              subtitle: const Text('Create, rename, reorder and delete'),
              onTap: () => context.push('/categories'),
            ),
          if (backend is ExtensionCapableBackend)
            ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('Extensions'),
              subtitle:
                  const Text('Install, update and remove source extensions'),
              onTap: () => context.push('/extensions'),
            ),
          if (backend == null)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title:
                  Text('Connect to a server to manage sources and extensions.'),
            ),
          if (backend != null)
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Disconnect'),
              subtitle: Text(
                  ref.watch(activeConnectionProvider)?.baseUrl.toString() ??
                      ''),
              onTap: () async {
                await ref.read(sessionStoreProvider).clear();
                ref.read(activeConnectionProvider.notifier).state = null;
                if (context.mounted) context.go('/');
              },
            ),
          const Divider(),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'Kai-Shelf',
            applicationLegalese: 'MIT License',
          ),
        ],
      ),
    );
  }
}
