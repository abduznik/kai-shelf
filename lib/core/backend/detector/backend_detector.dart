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

  /// POST doesn't auto-follow 3xx redirects on native platforms — dart:io's
  /// HttpClient (what package:http delegates to off web) only auto-follows
  /// GET/HEAD, per RFC 7231's requirement that a client confirm before
  /// resubmitting a POST body to a new location. A browser's fetch() (used
  /// on Flutter Web) follows POST redirects transparently, which is why a
  /// server that redirects bare-http:// to https:// silently failed
  /// detection on Android/Windows/etc. while working on web. Confirmed
  /// against a real duckdns-hosted server that 308s http -> https. Follow
  /// one redirect hop manually rather than relying on the client to do it,
  /// and report back the URL actually reached — the caller needs this to
  /// store the working scheme/host, not the original guess, or every
  /// later GraphQL call would hit the same un-followed-redirect problem.
  Future<({http.Response response, Uri finalUrl})> _postFollowingRedirect(
    Uri url,
    Map<String, String> headers,
    String body,
  ) async {
    final response =
        await _client.post(url, headers: headers, body: body).timeout(_timeout);
    if ((response.statusCode == 301 ||
            response.statusCode == 302 ||
            response.statusCode == 307 ||
            response.statusCode == 308) &&
        response.headers['location'] != null) {
      final redirectUrl = Uri.parse(response.headers['location']!);
      final redirected = await _client
          .post(redirectUrl, headers: headers, body: body)
          .timeout(_timeout);
      return (response: redirected, finalUrl: redirectUrl.replace(path: ''));
    }
    return (response: response, finalUrl: url.replace(path: ''));
  }

  /// GET does auto-follow redirects on native platforms (unlike POST), but
  /// package:http's plain `Client.get()`/`Response` silently discards the
  /// post-redirect URL — `Response` only extends `BaseResponse`, not
  /// `BaseResponseWithUrl`, so `response.request.url` still reports the
  /// original pre-redirect URL even though the request itself succeeded
  /// past the redirect. Using `send()` directly exposes the real one via
  /// `BaseResponseWithUrl.url` on the returned `StreamedResponse`.
  Future<({http.Response response, Uri finalUrl})> _getWithFinalUrl(
      Uri url) async {
    final streamed =
        await _client.send(http.Request('GET', url)).timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
    final finalUrl = streamed is http.BaseResponseWithUrl
        ? (streamed as http.BaseResponseWithUrl).url
        : url;
    return (response: response, finalUrl: finalUrl.replace(path: ''));
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
        return DetectionResult(
            type: result.type, normalizedBaseUrl: result.resolvedUrl);
      }
    }
    return null;
  }

  Future<_ProbeMatch?> _probeSuwayomi(Uri baseUrl) async {
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
      final (response: response, finalUrl: finalUrl) =
          await _postFollowingRedirect(
        baseUrl.replace(path: '/api/graphql'),
        {'Content-Type': 'application/json'},
        jsonEncode({'query': '{ aboutServer { buildType version } }'}),
      );

      if (response.statusCode == 401) {
        return _ProbeMatch(BackendType.suwayomi, finalUrl);
      }

      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      final data = body is Map ? body['data'] : null;
      final aboutServer = data is Map ? data['aboutServer'] : null;
      if (aboutServer is Map && aboutServer.containsKey('version')) {
        return _ProbeMatch(BackendType.suwayomi, finalUrl);
      }
    } catch (_) {
      // Not reachable, not Suwayomi, or not JSON — not a match.
    }
    return null;
  }

  Future<_ProbeMatch?> _probeKomga(Uri baseUrl) async {
    try {
      // /api/v2/users/me is auth-gated (401 with no guaranteed body shape
      // from Spring Security's default entry point) so it can't be used
      // for detection. /api/v1/claim is explicitly unauthenticated in
      // Komga's OpenAPI spec and returns a Komga-specific {isClaimed} JSON
      // shape regardless of whether the instance has an admin set up.
      final (response: response, finalUrl: finalUrl) = await _getWithFinalUrl(
        baseUrl.replace(path: '/api/v1/claim'),
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is Map && body.containsKey('isClaimed')) {
        return _ProbeMatch(BackendType.komga, finalUrl);
      }
    } catch (_) {}
    return null;
  }

  Future<_ProbeMatch?> _probeKavita(Uri baseUrl) async {
    try {
      final (response: response, finalUrl: finalUrl) = await _getWithFinalUrl(
        baseUrl.replace(path: '/api/Health'),
      );
      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('application/json') ||
            contentType.contains('text/plain')) {
          return _ProbeMatch(BackendType.kavita, finalUrl);
        }
      }
    } catch (_) {}
    return null;
  }

  void dispose() => _client.close();
}

class _ProbeMatch {
  const _ProbeMatch(this.type, this.resolvedUrl);
  final BackendType type;
  final Uri resolvedUrl;
}
