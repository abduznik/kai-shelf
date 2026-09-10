import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

class DetectionResult {
  const DetectionResult({required this.type, required this.normalizedBaseUrl});

  final BackendType type;
  final Uri normalizedBaseUrl;
}

/// Probes a raw server URL against each backend's distinctive endpoints and
/// picks the first unambiguous match by response shape (not just reachability
/// — multiple servers could be reachable at a given host, but only one is
/// the correct identification for that URL).
class BackendDetector {
  BackendDetector({http.Client? client, Duration? timeout})
      : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 4);

  final http.Client _client;
  final Duration _timeout;

  Uri _normalize(String rawUrlInput) {
    var input = rawUrlInput.trim();
    if (!input.startsWith('http://') && !input.startsWith('https://')) {
      input = 'http://$input';
    }
    final uri = Uri.parse(input);
    // Strip any trailing path the user might have pasted in.
    return uri.replace(path: '');
  }

  Future<DetectionResult?> detect(String rawUrlInput) async {
    final baseUrl = _normalize(rawUrlInput);

    final results = await Future.wait([
      _probeSuwayomi(baseUrl),
      _probeKomga(baseUrl),
      _probeKavita(baseUrl),
    ]);

    for (final result in results) {
      if (result != null) {
        return DetectionResult(type: result, normalizedBaseUrl: baseUrl);
      }
    }
    return null;
  }

  Future<BackendType?> _probeSuwayomi(Uri baseUrl) async {
    try {
      final response = await _client
          .get(baseUrl.replace(path: '/api/v1/settings/about'))
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is Map &&
          body.containsKey('buildType') &&
          body.containsKey('version')) {
        return BackendType.suwayomi;
      }
    } catch (_) {
      // Not reachable, not Suwayomi, or not JSON — not a match.
    }
    return null;
  }

  Future<BackendType?> _probeKomga(Uri baseUrl) async {
    try {
      final response = await _client
          .get(baseUrl.replace(path: '/api/v2/users/me'))
          .timeout(_timeout);
      // Komga responds 401 Unauthorized with its own error envelope when
      // hit without credentials — that shape is itself the fingerprint.
      if (response.statusCode == 401 || response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('application/json')) {
          return BackendType.komga;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<BackendType?> _probeKavita(Uri baseUrl) async {
    try {
      final response = await _client
          .get(baseUrl.replace(path: '/api/Health'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('application/json') ||
            contentType.contains('text/plain')) {
          return BackendType.kavita;
        }
      }
    } catch (_) {}
    return null;
  }

  void dispose() => _client.close();
}
