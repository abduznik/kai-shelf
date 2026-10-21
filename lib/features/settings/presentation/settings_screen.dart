import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/server_backend.dart';
import '../../../core/providers/app_version_provider.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/providers/incognito_provider.dart';
import '../../../core/providers/reader_prefs_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/update/external_link.dart';
import '../../../core/update/update_check_provider.dart';
import 'widgets/choice_dialog.dart';
import 'widgets/update_widgets.dart';

const List<(ThemeMode, String)> _themeChoices = [
  (ThemeMode.system, 'System'),
  (ThemeMode.light, 'Light'),
  (ThemeMode.dark, 'Dark'),
];

const List<(ReaderMode, String)> _modeChoices = [
  (ReaderMode.paged, 'Paged'),
  (ReaderMode.webtoon, 'Webtoon'),
];

const List<(ReadingDirection, String)> _directionChoices = [
  (ReadingDirection.ltr, 'Left to right'),
  (ReadingDirection.rtl, 'Right to left'),
];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Opportunistic: the provider throttles this to one request a day and
    // swallows every failure, so opening Settings never waits or errors.
    unawaited(ref.read(updateCheckProvider.notifier).check());
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(activeBackendProvider);
    final updateAvailable = ref.watch(updateAvailabilityProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const UpdatePromptBanner(),
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
          const _SectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            subtitle: Text(_themeLabel(ref.watch(themeModeProvider))),
            onTap: () async {
              final picked = await showChoiceDialog<ThemeMode>(
                context: context,
                title: 'Theme',
                selected: ref.read(themeModeProvider),
                choices: _themeChoices,
              );
              if (picked != null) {
                await ref.read(themeModeProvider.notifier).setThemeMode(picked);
              }
            },
          ),
          const _SectionHeader('Reading defaults'),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Reading mode'),
            subtitle: Text(switch (ref.watch(readerModeProvider)) {
              ReaderMode.paged => 'Paged',
              ReaderMode.webtoon => 'Webtoon',
            }),
            onTap: () async {
              final picked = await showChoiceDialog<ReaderMode>(
                context: context,
                title: 'Reading mode',
                selected: ref.read(readerModeProvider),
                choices: _modeChoices,
              );
              if (picked != null) {
                await ref.read(readerModeProvider.notifier).setMode(picked);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.swipe_outlined),
            title: const Text('Reading direction'),
            subtitle: Text(switch (ref.watch(readingDirectionProvider)) {
              ReadingDirection.ltr => 'Left to right',
              ReadingDirection.rtl => 'Right to left',
            }),
            onTap: () async {
              final picked = await showChoiceDialog<ReadingDirection>(
                context: context,
                title: 'Reading direction',
                selected: ref.read(readingDirectionProvider),
                choices: _directionChoices,
              );
              if (picked != null) {
                await ref
                    .read(readingDirectionProvider.notifier)
                    .setDirection(picked);
              }
            },
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
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Downloads'),
            subtitle: const Text('Queued and finished downloads'),
            onTap: () => context.push('/downloads'),
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
          if (updateAvailable != null)
            ListTile(
              leading: const Icon(Icons.system_update_alt),
              title: const Text('Update available'),
              subtitle: Text('${updateAvailable.tag} — open the release page'),
              onTap: () => openExternalLink(
                context,
                ref,
                updateAvailable.releaseUrl,
              ),
            ),
          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('Version'),
            subtitle: ref.watch(packageInfoProvider).when(
                  data: (info) => Text(formatAppVersion(info)),
                  loading: () => const Text('…'),
                  error: (error, stackTrace) => const Text('Unavailable'),
                ),
          ),
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

String _themeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };

/// Small group label; Settings stays one flat, scrollable list.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      );
}
