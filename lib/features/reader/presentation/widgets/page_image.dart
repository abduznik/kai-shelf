import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/backend/models.dart';
import '../../../../core/widgets/authenticated_image.dart';

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

    return AuthenticatedImage(
      imageUrl: page.imageUrl,
      headers: page.extraHeaders,
      fit: fit,
      placeholder: (context) =>
          const Center(child: CircularProgressIndicator()),
      errorWidget: (context, error) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
