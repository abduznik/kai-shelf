import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/recommendations/anilist_client.dart';

/// Opens the all-sources search pre-filled with a recommended title, so the
/// user can pick which source to preview or add it from.
void searchSourcesFor(BuildContext context, AniListRecommendation rec) {
  context.push('/discover/all?q=${Uri.encodeQueryComponent(rec.searchTitle)}');
}

/// A tappable AniList cover with its title. AniList images are public, so a
/// plain network image is enough (no auth headers like server covers).
class RecommendationCover extends StatelessWidget {
  const RecommendationCover({
    super.key,
    required this.recommendation,
    this.subtitle,
  });

  final AniListRecommendation recommendation;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.menu_book_outlined)),
    );
    return InkWell(
      onTap: () => searchSourcesFor(context, recommendation),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.expand(
                child: recommendation.coverUrl == null
                    ? placeholder
                    : Image.network(
                        recommendation.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => placeholder,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            recommendation.searchTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.outline),
            ),
        ],
      ),
    );
  }
}
