import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hands a URL to the platform browser. Injectable so tests can assert the
/// target without a platform channel.
typedef ExternalUrlOpener = Future<bool> Function(String url);

Future<bool> _openExternal(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

final externalUrlOpenerProvider =
    Provider<ExternalUrlOpener>((ref) => _openExternal);

/// Opens [url] outside the app. Where no browser can be launched the link is
/// copied to the clipboard instead, so it stays reachable — never an error
/// dialog, never a dead end.
Future<void> openExternalLink(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  final opened = await ref.read(externalUrlOpenerProvider)(url);
  if (opened || !context.mounted) return;
  try {
    await Clipboard.setData(ClipboardData(text: url));
  } catch (_) {
    // Clipboard unavailable: nothing else to try; still no error surface.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Link copied: $url')),
    );
  }
}
