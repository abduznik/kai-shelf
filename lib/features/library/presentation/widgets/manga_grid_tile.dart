import 'package:flutter/material.dart';

import '../../../../core/backend/models.dart';
import '../../../../core/widgets/authenticated_image.dart';
import 'library_filter_sheet.dart';

class MangaGridTile extends StatelessWidget {
  const MangaGridTile({super.key, required this.manga, required this.onTap});

  final KsManga manga;
  final VoidCallback onTap;

  /// One announcement for the whole tile: cover, title and the title's
  /// status arrive together instead of a bare image and a bare title
  /// (issue #16). [KsManga] carries no per-title read progress, so the
  /// publication status is the reading state available here.
  String get _semanticsLabel => manga.status == MangaStatus.unknown
      ? manga.title
      : '${manga.title}, ${statusLabel(manga.status)}';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: _semanticsLabel,
      onTap: onTap,
      // Fold the cover, its placeholder and the title text into the single
      // label above rather than dropping them silently.
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: manga.coverUrl != null
                      ? AuthenticatedImage(
                          imageUrl: manga.coverUrl!,
                          headers: manga.coverHeaders,
                          fit: BoxFit.cover,
                          placeholder: (context) => Container(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                          errorWidget: (context, error) => Container(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        )
                      : Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(Icons.menu_book_outlined),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              manga.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
