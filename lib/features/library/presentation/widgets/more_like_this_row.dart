import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/server_backend.dart';
import '../../../../core/providers/backend_providers.dart';
import '../../../../core/providers/incognito_provider.dart';
import '../../../../core/providers/recommendation_providers.dart';
import 'recommendation_cover.dart';

/// Horizontal "More like this" strip for the manga detail screen. It stays
/// invisible while loading, on failure and when AniList has nothing, because
/// recommendations are optional and must never push the real content around
/// or show an error. Hidden in incognito mode (nothing is sent to AniList)
/// and entirely for backends that cannot search sources,
/// since tapping a title has nowhere to go there.
class MoreLikeThisRow extends ConsumerWidget {
  const MoreLikeThisRow({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(activeBackendProvider) is! SourceCapableBackend) {
      return const SizedBox.shrink();
    }
    // Incognito promises to leave no trace, and this row would otherwise
    // send the title being browsed to a third party (AniList).
    if (ref.watch(incognitoProvider)) return const SizedBox.shrink();
    final recs = ref.watch(titleRecommendationsProvider(title)).valueOrNull;
    final shown = [
      for (final r in recs ?? const [])
        if (!r.isAdult) r
    ];
    if (shown.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('More like this',
              style: Theme.of(context).textTheme.titleSmall),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: shown.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => SizedBox(
              width: 100,
              child: RecommendationCover(recommendation: shown[i]),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
