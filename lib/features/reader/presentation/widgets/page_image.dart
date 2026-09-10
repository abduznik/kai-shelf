import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/backend/models.dart';

/// Renders a single reader page, loading from a downloaded local file when
/// available and falling back to the network URL (with any auth headers
/// the backend requires) otherwise.
class PageImage extends StatelessWidget {
  const PageImage({super.key, required this.page, required this.fit});

  final KsPage page;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (page.isLocal) {
      return Image.file(
        File(page.localPath!),
        fit: fit,
        errorBuilder: (context, error, stackTrace) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    }

    return CachedNetworkImage(
      imageUrl: page.imageUrl,
      httpHeaders: page.extraHeaders,
      fit: fit,
      placeholder: (context, url) =>
          const Center(child: CircularProgressIndicator()),
      errorWidget: (context, url, error) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
