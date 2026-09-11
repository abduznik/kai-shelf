import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Loads a network image with custom auth headers, working around
/// cached_network_image's web platform not reliably respecting
/// `httpHeaders` (a years-old, still-open upstream limitation — confirmed
/// against a live server where authenticated covers 401'd on web despite
/// headers being passed). On web, fetches bytes manually via `http.get`
/// and renders with `Image.memory`; elsewhere, uses CachedNetworkImage
/// as normal, since headers work correctly there.
class AuthenticatedImage extends StatelessWidget {
  const AuthenticatedImage({
    super.key,
    required this.imageUrl,
    this.headers,
    this.fit,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final Map<String, String>? headers;
  final BoxFit? fit;
  final WidgetBuilder? placeholder;
  final Widget Function(BuildContext context, Object error)? errorWidget;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || headers == null || headers!.isEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: headers,
        fit: fit,
        placeholder: placeholder == null
            ? null
            : (context, url) => placeholder!(context),
        errorWidget: errorWidget == null
            ? null
            : (context, url, error) => errorWidget!(context, error),
      );
    }

    return FutureBuilder<Uint8List>(
      future: http.get(Uri.parse(imageUrl), headers: headers).then((response) {
        if (response.statusCode != 200) {
          throw Exception('Failed to load image (${response.statusCode})');
        }
        return response.bodyBytes;
      }),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return errorWidget?.call(context, snapshot.error!) ??
              const SizedBox.shrink();
        }
        if (!snapshot.hasData) {
          return placeholder?.call(context) ?? const SizedBox.shrink();
        }
        return Image.memory(snapshot.data!, fit: fit);
      },
    );
  }
}
