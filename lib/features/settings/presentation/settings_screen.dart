import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/server_backend.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/incognito_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(activeBackendProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Incognito mode'),
            subtitle: const Text(
                'Reading is not saved: no progress, history, read marks '
                'or background downloads'),
            value: ref.watch(incognitoProvider),
            onChanged: (value) =>
                ref.read(incognitoProvider.notifier).setEnabled(value),
          ),
          const Divider(),
          if (backend is SourceCapableBackend)
            ListTile(
              leading: const Icon(Icons.explore_outlined),
              title: const Text('Sources'),
              subtitle:
                  const Text('Browse, filter and search installed sources'),
              onTap: () => context.push('/discover'),
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
