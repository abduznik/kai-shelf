import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/backend/detector/backend_detector.dart';
import 'package:kai_shelf/core/backend/models.dart';

void main() {
  group('BackendDetector', () {
    test('identifies a Suwayomi server from the /settings/about shape',
        () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/settings/about') {
          return http.Response(
            jsonEncode({'buildType': 'Stable', 'version': '1.0.0'}),
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

    test('identifies a Komga server from its authenticated-me endpoint shape',
        () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v2/users/me') {
          return http.Response(
            jsonEncode({'error': 'Unauthorized'}),
            401,
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
  });
}
