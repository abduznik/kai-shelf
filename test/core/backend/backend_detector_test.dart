import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/backend/detector/backend_detector.dart';
import 'package:kai_shelf/core/backend/models.dart';

import 'opds/opds_fixtures.dart';

void main() {
  group('BackendDetector', () {
    test(
        'a real Komga (401 JSON on every unknown path) is not mistaken for '
        'a BASIC_AUTH Suwayomi', () async {
      // Captured from a live Komga: Spring Security answers /api/graphql
      // and /api/Health with 401, while /api/v1/claim is open.
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/claim') {
          return http.Response(jsonEncode({'isClaimed': true}), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(
            jsonEncode({
              'timestamp': '2026-10-05T19:58:42.167+00:00',
              'status': 401,
              'error': 'Unauthorized',
              'message': 'Unauthorized',
              'path': request.url.path,
            }),
            401,
            headers: {'content-type': 'application/json'});
      });

      final detector = BackendDetector(client: client);
      final result = await detector.detect('http://example.com:25600');

      expect(result!.type, BackendType.komga);
    });

    test(
        'identifies a Suwayomi server from the unauthenticated aboutServer GraphQL query',
        () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/graphql' && request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'data': {
                'aboutServer': {'buildType': 'Stable', 'version': '1.0.0'},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final detector = BackendDetector(client: client);
      final result = await detector.detect('http://example.com:4567');

      expect(result, isNotNull);
      expect(result!.type, BackendType.suwayomi);
    });

    test(
        'identifies a BASIC_AUTH-mode Suwayomi server from a 401 at POST /api/graphql',
        () async {
      // Confirmed against a live server: with server.authMode = BASIC_AUTH,
      // Suwayomi gates aboutServer too (unlike its GraphQL-session default,
      // which leaves aboutServer exempt), returning 401. Also confirmed in
      // a real browser: the WWW-Authenticate header on that response is
      // NOT readable via fetch() cross-origin (not CORS-safelisted, and
      // this server doesn't send Access-Control-Expose-Headers) — so
      // detection can only key off the status code at this specific path,
      // not the header.
      final client = MockClient((request) async {
        if (request.url.path == '/api/graphql' && request.method == 'POST') {
          return http.Response('Unauthorized', 401,
              headers: {'content-type': 'text/plain'});
        }
        return http.Response('not found', 404);
      });

      final detector = BackendDetector(client: client);
      final result = await detector.detect('http://example.com:4567');

      expect(result, isNotNull);
      expect(result!.type, BackendType.suwayomi);
    });

    test(
        'follows a single 308 redirect on the Suwayomi POST probe (bare http:// against an https-only server)',
        () async {
      // Confirmed against a real duckdns-hosted server: it 308-redirects
      // plain http:// to https://, and dart:io's HttpClient (what
      // package:http uses off web) does not auto-follow redirects on POST
      // — only GET/HEAD. This previously meant detection silently failed
      // on Android/Windows/etc. for any server the user reached over bare
      // http while working fine on Flutter Web, where fetch() follows POST
      // redirects transparently.
      final client = MockClient((request) async {
        if (request.url.scheme == 'http' &&
            request.url.path == '/api/graphql') {
          return http.Response(
            '',
            308,
            headers: {'location': 'https://example.com:4567/api/graphql'},
          );
        }
        if (request.url.scheme == 'https' &&
            request.url.path == '/api/graphql') {
          return http.Response('Unauthorized', 401,
              headers: {'content-type': 'text/plain'});
        }
        return http.Response('not found', 404);
      });

      final detector = BackendDetector(client: client);
      // Explicit http:// so this test exercises the redirect-follow path
      // directly, rather than the https-first probe order picking it up
      // without a redirect ever happening.
      final result = await detector.detect('http://example.com:4567');

      expect(result, isNotNull);
      expect(result!.type, BackendType.suwayomi);
      // The stored connection URL must be the one actually reached
      // (https), not the original http:// guess — otherwise every later
      // GraphQL call via SuwayomiBackend would hit this same
      // un-followed-POST-redirect problem again.
      expect(result.normalizedBaseUrl.scheme, 'https');
    });

    test('tries https:// before http:// when the user gives no scheme',
        () async {
      var httpsAttempted = false;
      var httpAttempted = false;
      final client = MockClient((request) async {
        if (request.url.scheme == 'https' &&
            request.url.path == '/api/graphql') {
          httpsAttempted = true;
          return http.Response('Unauthorized', 401,
              headers: {'content-type': 'text/plain'});
        }
        if (request.url.scheme == 'http' &&
            request.url.path == '/api/graphql') {
          httpAttempted = true;
        }
        return http.Response('not found', 404);
      });

      final detector = BackendDetector(client: client);
      final result = await detector.detect('example.com:4567');

      expect(result, isNotNull);
      expect(result!.type, BackendType.suwayomi);
      expect(result.normalizedBaseUrl.scheme, 'https');
      expect(httpsAttempted, isTrue);
      expect(httpAttempted, isFalse);
    });

    test('falls back to http:// when https:// has nothing at that host',
        () async {
      final client = MockClient((request) async {
        if (request.url.scheme == 'http' &&
            request.url.path == '/api/graphql') {
          return http.Response('Unauthorized', 401,
              headers: {'content-type': 'text/plain'});
        }
        return http.Response('not found', 404);
      });

      final detector = BackendDetector(client: client);
      final result = await detector.detect('example.com:4567');

      expect(result, isNotNull);
      expect(result!.type, BackendType.suwayomi);
      expect(result.normalizedBaseUrl.scheme, 'http');
    });

    test('identifies a Komga server from its unauthenticated claim endpoint',
        () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/claim') {
          return http.Response(
            jsonEncode({'isClaimed': true}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final detector = BackendDetector(client: client);
      final result = await detector.detect('example.com:8080');

      expect(result, isNotNull);
      expect(result!.type, BackendType.komga);
    });

    test('identifies a Kavita server from its health endpoint', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/Health') {
          return http.Response('Healthy', 200,
              headers: {'content-type': 'text/plain'});
        }
        return http.Response('not found', 404);
      });

      final detector = BackendDetector(client: client);
      final result = await detector.detect('https://example.com');

      expect(result, isNotNull);
      expect(result!.type, BackendType.kavita);
    });

    test('returns null when nothing matches', () async {
      final client =
          MockClient((request) async => http.Response('not found', 404));

      final detector = BackendDetector(client: client);
      final result = await detector.detect('http://example.com');

      expect(result, isNull);
    });

    test(
        'a 404 at POST /api/graphql (path not exposed by this server) does not match Suwayomi',
        () async {
      final client =
          MockClient((request) async => http.Response('not found', 404));

      final detector = BackendDetector(client: client);
      final result = await detector.detect('http://example.com:4567');

      expect(result, isNull);
    });

    test('identifies an OPDS catalog from its Atom catalog relations',
        () async {
      // Confirmed against a real public catalog (Office of the Historian,
      // https://history.state.gov/api/v1/catalog): the response comes back
      // as text/xml — detection has to read the document, not the content
      // type — and the catalog lives at a path that must survive into the
      // stored connection URL.
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/catalog') {
          return http.Response(navRootFeedXml, 200,
              headers: {'content-type': 'text/xml;charset=utf-8'});
        }
        return http.Response('not found', 404);
      });

      final detector = BackendDetector(client: client);
      final result =
          await detector.detect('https://history.example/api/v1/catalog');

      expect(result, isNotNull);
      expect(result!.type, BackendType.opds);
      // Unlike the server probes, which rebuild paths from the origin, the
      // OPDS probe must keep the catalog path the user typed.
      expect(result.normalizedBaseUrl.path, '/api/v1/catalog');
    });

    test('detects an OPDS catalog on the http:// fallback candidate', () async {
      final client = MockClient((request) async {
        if (request.url.scheme == 'http') {
          return http.Response(navRootFeedXml, 200,
              headers: {'content-type': 'application/atom+xml'});
        }
        return http.Response('not found', 404);
      });

      final detector = BackendDetector(client: client);
      final result = await detector.detect('library.example/opds/root.xml');

      expect(result, isNotNull);
      expect(result!.type, BackendType.opds);
      expect(result.normalizedBaseUrl.scheme, 'http');
    });

    test('detects a catalog that only uses subsection relations', () async {
      // Calibre-Web-style navigation feeds use rel="subsection" without any
      // http://opds-spec.org/sort/... link.
      final client = MockClient((request) async {
        if (request.url.path == '/opds') {
          return http.Response(navRootFeedNoSearchXml, 200,
              headers: {'content-type': 'application/atom+xml'});
        }
        return http.Response('not found', 404);
      });

      final detector = BackendDetector(client: client);
      final result = await detector.detect('https://library.example/opds');

      expect(result, isNotNull);
      expect(result!.type, BackendType.opds);
    });

    test('a real Komga is never mistaken for an OPDS catalog', () async {
      // Komga serves an HTML UI at / and 401 JSON on unknown API paths.
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/claim') {
          return http.Response(jsonEncode({'isClaimed': true}), 200,
              headers: {'content-type': 'application/json'});
        }
        if (request.url.path == '/') {
          return http.Response(htmlPage, 200,
              headers: {'content-type': 'text/html'});
        }
        return http.Response(
            jsonEncode({'status': 401, 'path': request.url.path}), 401,
            headers: {'content-type': 'application/json'});
      });

      final detector = BackendDetector(client: client);
      final result = await detector.detect('https://komga.example/');

      expect(result!.type, BackendType.komga);
    });

    test('a real Kavita is never mistaken for an OPDS catalog', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/Health') {
          return http.Response('Healthy', 200,
              headers: {'content-type': 'text/plain'});
        }
        if (request.url.path == '/') {
          return http.Response(htmlPage, 200,
              headers: {'content-type': 'text/html'});
        }
        return http.Response('not found', 404);
      });

      final detector = BackendDetector(client: client);
      final result = await detector.detect('https://kavita.example/');

      expect(result!.type, BackendType.kavita);
    });

    test('a real Suwayomi is never mistaken for an OPDS catalog', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/graphql' && request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'data': {
                'aboutServer': {'buildType': 'Stable', 'version': '1.0.0'},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final detector = BackendDetector(client: client);
      final result = await detector.detect('https://suwayomi.example/');

      expect(result!.type, BackendType.suwayomi);
    });

    test('a plain Atom feed without OPDS relations is not a catalog', () async {
      // An Atom blog feed at the origin root: well-formed XML, an atom:feed
      // document, but no OPDS catalog relations anywhere.
      final client = MockClient((request) async => http.Response(
          blogAtomFeedXml, 200,
          headers: {'content-type': 'application/atom+xml'}));

      final detector = BackendDetector(client: client);
      final result = await detector.detect('https://blog.example/');

      expect(result, isNull);
    });
  });
}
