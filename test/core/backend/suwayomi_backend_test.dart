import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/backend/auth_credentials.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/suwayomi/suwayomi_backend.dart';

/// Mocked responses model the real behavior confirmed against a live
/// Suwayomi instance: auth is server.authMode = BASIC_AUTH, checked on
/// every request via the Authorization header — there is no separate
/// login/session step. @requireAuth-gated queries (categories, mangas,
/// ...) return HTTP 200 with a GraphQL `errors[]` body — never an HTTP
/// 401 — when the header is missing or wrong.
http.Client _mockClient(
    {required bool requiresAuth, String? expectedBasicAuth}) {
  return MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final query = body['query'] as String;
    final authHeader = request.headers['Authorization'];

    if (query.contains('categories') ||
        query.contains('mangas') ||
        query.contains('category(')) {
      final authorized = !requiresAuth ||
          (expectedBasicAuth != null && authHeader == expectedBasicAuth);
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

String _basicAuthHeader(String username, String password) {
  return 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
}

void main() {
  group('SuwayomiBackend.login', () {
    test('succeeds with correct Basic Auth credentials', () async {
      final backend = SuwayomiBackend(
        _connectionInfo(),
        httpClient: _mockClient(
          requiresAuth: true,
          expectedBasicAuth: _basicAuthHeader('egg', 'Chonk420'),
        ),
      );

      final result = await backend.login(
        const AuthCredentials.suwayomi(username: 'egg', password: 'Chonk420'),
      );

      expect(result.success, isTrue);
      expect(
        result.connectionInfo!.extraHeaders['Authorization'],
        _basicAuthHeader('egg', 'Chonk420'),
      );
    });

    test('fails with a clear message on wrong credentials', () async {
      final backend = SuwayomiBackend(
        _connectionInfo(),
        httpClient: _mockClient(
          requiresAuth: true,
          expectedBasicAuth: _basicAuthHeader('egg', 'Chonk420'),
        ),
      );

      final result = await backend.login(
        const AuthCredentials.suwayomi(username: 'egg', password: 'wrong'),
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
      expect(result.connectionInfo!.extraHeaders, isEmpty);
    });
  });

  group('SuwayomiBackend.getMangaList', () {
    test(
        'queries the category relation when libraryId is given, and client-side filters by search',
        () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final query = body['query'] as String;
        if (query.contains('CategoryMangaList')) {
          expect((body['variables'] as Map)['categoryId'], 0);
          return http.Response(
            jsonEncode({
              'data': {
                'category': {
                  'mangas': {
                    'nodes': [
                      {'id': 1, 'title': 'One Piece'},
                      {'id': 2, 'title': 'Naruto'},
                    ],
                  },
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final backend = SuwayomiBackend(_connectionInfo(), httpClient: client);
      final all = await backend.getMangaList(libraryId: '0');
      expect(all.map((m) => m.title), ['One Piece', 'Naruto']);

      final filtered =
          await backend.getMangaList(libraryId: '0', searchQuery: 'naru');
      expect(filtered.map((m) => m.title), ['Naruto']);
    });

    test(
        'queries the top-level mangas field with a server-side title filter when no libraryId is given',
        () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final query = body['query'] as String;
        if (query.contains('MangaList') &&
            !query.contains('CategoryMangaList')) {
          expect((body['variables'] as Map)['searchQuery'], 'vagabond');
          return http.Response(
            jsonEncode({
              'data': {
                'mangas': {
                  'nodes': [
                    {'id': 19, 'title': 'Vagabond'},
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

      final backend = SuwayomiBackend(_connectionInfo(), httpClient: client);
      final result = await backend.getMangaList(searchQuery: 'vagabond');

      expect(result, hasLength(1));
      expect(result.first.title, 'Vagabond');
    });

    test(
        'resolves cover URLs to absolute and attaches the current auth headers',
        () async {
      // Confirmed against a live BASIC_AUTH server: thumbnailUrl comes
      // back as a bare relative path ("/api/v1/manga/16/thumbnail") and
      // 401s without the same auth used for GraphQL — cached_network_image
      // needs both an absolute URL and the headers to load it.
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final query = body['query'] as String;
        if (query.contains('categories')) {
          return http.Response(
            jsonEncode({
              'data': {
                'categories': {'nodes': []}
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (query.contains('MangaList') &&
            !query.contains('CategoryMangaList')) {
          return http.Response(
            jsonEncode({
              'data': {
                'mangas': {
                  'nodes': [
                    {
                      'id': 16,
                      'title': 'Hajime no Ippo',
                      'thumbnailUrl': '/api/v1/manga/16/thumbnail'
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

      final backend = SuwayomiBackend(_connectionInfo(), httpClient: client);
      await backend.login(const AuthCredentials.suwayomi(
          username: 'egg', password: 'Chonk420'));
      final result = await backend.getMangaList();

      expect(result.first.coverUrl,
          'http://example.com:4567/api/v1/manga/16/thumbnail');
      expect(result.first.coverHeaders?['Authorization'], isNotNull);
    });
  });

  group('SuwayomiBackend.getPages', () {
    test('calls fetchChapterPages and maps its returned page paths', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final query = body['query'] as String;
        if (query.contains('FetchChapterPages')) {
          expect((body['variables'] as Map)['chapterId'], 1682);
          return http.Response(
            jsonEncode({
              'data': {
                'fetchChapterPages': {
                  'pages': [
                    '/api/v1/manga/19/chapter/1/page/0',
                    '/api/v1/manga/19/chapter/1/page/1',
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

      final backend = SuwayomiBackend(_connectionInfo(), httpClient: client);
      final pages = await backend.getPages('1682');

      expect(pages, hasLength(2));
      expect(pages[0].imageUrl, contains('/api/v1/manga/19/chapter/1/page/0'));
      expect(pages[1].imageUrl, contains('/api/v1/manga/19/chapter/1/page/1'));
    });
  });
}
