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
      // With server.authMode left at its GraphQL-session default,
      // aboutServer is exempt from the @requireAuth directive and returns
      // 200 unauthenticated. But with authMode = BASIC_AUTH (the only mode
      // Kai-Shelf's login actually supports — see SuwayomiBackend's doc
      // comment), Suwayomi gates EVERY GraphQL field behind auth,
      // aboutServer included — confirmed against a live BASIC_AUTH
      // instance, which 401s here.
      //
      // Can't fingerprint via the WWW-Authenticate header on that 401:
      // confirmed in a real browser that fetch() doesn't expose it
      // cross-origin without the server sending
      // Access-Control-Expose-Headers, which this server doesn't — a
      // non-CORS-safelisted response header is simply invisible to web JS.
      // Instead, treat any 401 specifically at POST /api/graphql as the
      // fingerprint: Komga and Kavita don't expose this path at all, so
      // they'd 404 here, not 401.
      final response = await _client
          .post(
            baseUrl.replace(path: '/api/graphql'),
            headers: {'Content-Type': 'application/json'},
            body:
                jsonEncode({'query': '{ aboutServer { buildType version } }'}),
          )
          .timeout(_timeout);

      if (response.statusCode == 401) {
        return BackendType.suwayomi;
      }

      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      final data = body is Map ? body['data'] : null;
      final aboutServer = data is Map ? data['aboutServer'] : null;
      if (aboutServer is Map && aboutServer.containsKey('version')) {
        return BackendType.suwayomi;
      }
    } catch (_) {
      // Not reachable, not Suwayomi, or not JSON — not a match.
    }
    return null;
  }

  Future<BackendType?> _probeKomga(Uri baseUrl) async {
    try {
      // /api/v2/users/me is auth-gated (401 with no guaranteed body shape
      // from Spring Security's default entry point) so it can't be used
      // for detection. /api/v1/claim is explicitly unauthenticated in
      // Komga's OpenAPI spec and returns a Komga-specific {isClaimed} JSON
      // shape regardless of whether the instance has an admin set up.
      final response = await _client
          .get(baseUrl.replace(path: '/api/v1/claim'))
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is Map && body.containsKey('isClaimed')) {
        return BackendType.komga;
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
