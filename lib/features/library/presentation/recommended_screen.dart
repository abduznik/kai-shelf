import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/recommendation_providers.dart';
import 'widgets/recommendation_cover.dart';

/// "Recommended for you": titles AniList suggests for a sample of the user's
/// library, minus anything already in it. Results are cached for the session;
/// the refresh button re-queries AniList.
class RecommendedScreen extends ConsumerWidget {
  const RecommendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(libraryRecommendationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recommended for you'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(aniListClientProvider).clearCache();
              ref.invalidate(libraryRecommendationsProvider);
            },
          ),
        ],
      ),
      body: async.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'No recommendations yet. Add a few titles to your library '
                    'and check again.'),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.58,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => RecommendationCover(
              recommendation: items[i].recommendation,
              subtitle: items[i].votes > 1
                  ? 'Fits ${items[i].votes} of your titles'
                  : null,
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
      ),
    );
  }
}
