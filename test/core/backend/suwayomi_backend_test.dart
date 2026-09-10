import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/backend/auth_credentials.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/suwayomi/suwayomi_backend.dart';

/// Mocked responses model the real behavior confirmed against a live
/// Suwayomi instance: @requireAuth-gated queries (categories, mangas, ...)
/// return HTTP 200 with a GraphQL `errors[]` body — never an HTTP 401 —
/// when no/invalid credentials are supplied.
http.Client _mockClient({required bool requiresAuth, String? expectedBearer}) {
  return MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final query = body['query'] as String;
    final authHeader = request.headers['Authorization'];

    if (query.contains('mutation Login')) {
      final variables = body['variables'] as Map<String, dynamic>;
      if (variables['username'] == 'admin' &&
          variables['password'] == 'correct') {
        return http.Response(
          jsonEncode({
            'data': {
              'login': {
                '__typename': 'LoginPayload',
                'accessToken': 'access-123',
                'refreshToken': 'refresh-456',
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'errors': [
            {'message': 'Incorrect username or password.'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (query.contains('categories')) {
      final authorized = !requiresAuth ||
          (expectedBearer != null && authHeader == expectedBearer);
      if (!authorized) {
        return http.Response(
          jsonEncode({
            'errors': [
              {
                'message':
                    'Exception while fetching data (/categories) : Unauthorized'
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': {
            'categories': {
              '__typename': 'CategoryNodeList',
              'nodes': [
                {
                  '__typename': 'CategoryType',
                  'id': 1,
                  'name': 'Default',
                  'mangas': {'__typename': 'MangaNodeList', 'totalCount': 3},
                },
              ],
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    return http.Response('not found', 404);
  });
}

ServerConnectionInfo _connectionInfo() {
  return ServerConnectionInfo(
    serverId: 'server-1',
    displayName: 'test',
    baseUrl: Uri.parse('http://example.com:4567'),
    type: BackendType.suwayomi,
  );
}

void main() {
  group('SuwayomiBackend.login', () {
    test('logs in successfully and stores the returned access token', () async {
      final backend = SuwayomiBackend(
        _connectionInfo(),
        httpClient: _mockClient(
            requiresAuth: true, expectedBearer: 'Bearer access-123'),
      );

      final result = await backend.login(
        const AuthCredentials.suwayomi(username: 'admin', password: 'correct'),
      );

      expect(result.success, isTrue);
      expect(result.connectionInfo!.sessionToken, 'access-123');
      expect(result.connectionInfo!.refreshToken, 'refresh-456');
    });

    test('fails with a clear message on wrong credentials', () async {
      final backend = SuwayomiBackend(
        _connectionInfo(),
        httpClient: _mockClient(requiresAuth: true),
      );

      final result = await backend.login(
        const AuthCredentials.suwayomi(username: 'admin', password: 'wrong'),
      );

      expect(result.success, isFalse);
      expect(result.error, contains('Incorrect username or password'));
    });

    test(
        'rejects a blank-credential connect attempt against an auth-required server',
        () async {
      final backend = SuwayomiBackend(
        _connectionInfo(),
        httpClient: _mockClient(requiresAuth: true),
      );

      final result = await backend.login(const AuthCredentials.suwayomi());

      expect(result.success, isFalse);
      expect(result.error, contains('requires a username and password'));
    });

    test('accepts a blank-credential connect attempt against a no-auth server',
        () async {
      final backend = SuwayomiBackend(
        _connectionInfo(),
        httpClient: _mockClient(requiresAuth: false),
      );

      final result = await backend.login(const AuthCredentials.suwayomi());

      expect(result.success, isTrue);
    });
  });
}
