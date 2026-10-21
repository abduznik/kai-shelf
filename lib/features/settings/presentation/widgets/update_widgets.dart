import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/update/external_link.dart';
import '../../../../core/update/update_check_provider.dart';

/// The non-intrusive prompt from #14: one card while a newer release is
/// known, gone for good once "Later" is tapped for that exact version. A
/// newer release re-arms it; nothing else ever brings it back.
class UpdatePromptBanner extends ConsumerWidget {
  const UpdatePromptBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prompt = ref.watch(updatePromptProvider);
    if (prompt == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kai-Shelf ${prompt.tag} is out',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'A newer version is ready. Downloads are served on GitHub, '
              'outside the app.',
              style: theme.textTheme.bodyMedium,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(suppressedUpdateTagProvider.notifier)
                      .suppress(prompt.tag),
                  child: const Text('Later'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () =>
                      openExternalLink(context, ref, prompt.releaseUrl),
                  child: const Text('Open release page'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
