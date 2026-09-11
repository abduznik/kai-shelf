import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/backend/detector/backend_detector.dart';
import 'package:kai_shelf/core/backend/models.dart';

void main() {
  group('BackendDetector', () {
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
  });
}
