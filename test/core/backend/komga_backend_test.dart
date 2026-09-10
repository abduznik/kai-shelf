import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/backend/auth_credentials.dart';
import 'package:kai_shelf/core/backend/komga/komga_backend.dart';
import 'package:kai_shelf/core/backend/models.dart';

ServerConnectionInfo _connectionInfo() {
  return ServerConnectionInfo(
    serverId: 'server-1',
    displayName: 'test',
    baseUrl: Uri.parse('http://example.com:8080'),
    type: BackendType.komga,
  );
}

void main() {
  group('KomgaBackend.login', () {
    test('succeeds with Basic auth when email/password match', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v2/users/me') {
          final auth = request.headers['Authorization'];
          final expected =
              'Basic ${base64Encode(utf8.encode('user@example.com:correct'))}';
          if (auth == expected) {
            return http.Response(
              jsonEncode({'id': '1', 'email': 'user@example.com', 'roles': []}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('', 401);
        }
        return http.Response('not found', 404);
      });

      final backend = KomgaBackend(_connectionInfo(), httpClient: client);
      final result = await backend.login(
        const AuthCredentials.komgaPassword(
            email: 'user@example.com', password: 'correct'),
      );

      expect(result.success, isTrue);
    });

    test('succeeds with an API key', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v2/users/me') {
          if (request.headers['X-API-Key'] == 'my-api-key') {
            return http.Response(
              jsonEncode({'id': '1', 'email': 'user@example.com', 'roles': []}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('', 401);
        }
        return http.Response('not found', 404);
      });

      final backend = KomgaBackend(_connectionInfo(), httpClient: client);
      final result = await backend
          .login(const AuthCredentials.komgaApiKey(apiKey: 'my-api-key'));

      expect(result.success, isTrue);
      expect(result.connectionInfo!.apiKey, 'my-api-key');
    });

    test('fails with wrong credentials', () async {
      final client = MockClient((request) async => http.Response('', 401));

      final backend = KomgaBackend(_connectionInfo(), httpClient: client);
      final result = await backend.login(
        const AuthCredentials.komgaPassword(
            email: 'user@example.com', password: 'wrong'),
      );

      expect(result.success, isFalse);
    });
  });

  group('KomgaBackend data fetches', () {
    test('getLibraries maps a plain array response', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/libraries') {
          return http.Response(
            jsonEncode([
              {'id': 'lib1', 'name': 'Manga'},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final backend = KomgaBackend(_connectionInfo(), httpClient: client);
      final libraries = await backend.getLibraries();

      expect(libraries, hasLength(1));
      expect(libraries.first.id, 'lib1');
      expect(libraries.first.name, 'Manga');
    });

    test(
        'getMangaList reads series from the paged content wrapper and metadata title',
        () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/series') {
          return http.Response(
            jsonEncode({
              'content': [
                {
                  'id': 's1',
                  'name': 'fallback-name',
                  'metadata': {
                    'title': 'One Piece',
                    'summary': 'A pirate adventure',
                    'genres': ['Adventure', 'Action'],
                    'status': 'ONGOING',
                  },
                },
              ],
              'totalElements': 1,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final backend = KomgaBackend(_connectionInfo(), httpClient: client);
      final mangaList = await backend.getMangaList();

      expect(mangaList, hasLength(1));
      expect(mangaList.first.title, 'One Piece');
      expect(mangaList.first.description, 'A pirate adventure');
      expect(mangaList.first.genres, ['Adventure', 'Action']);
      expect(mangaList.first.status, MangaStatus.ongoing);
    });

    test('getChapters reads read progress from the nested readProgress object',
        () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/series/s1/books') {
          return http.Response(
            jsonEncode({
              'content': [
                {
                  'id': 'b1',
                  'seriesId': 's1',
                  'name': 'Chapter 1',
                  'number': 1,
                  'readProgress': {'page': 5, 'completed': true},
                },
                {
                  'id': 'b2',
                  'seriesId': 's1',
                  'name': 'Chapter 2',
                  'number': 2,
                  'readProgress': null,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final backend = KomgaBackend(_connectionInfo(), httpClient: client);
      final chapters = await backend.getChapters('s1');

      expect(chapters, hasLength(2));
      expect(chapters[0].read, isTrue);
      expect(chapters[0].lastPageRead, 5);
      expect(chapters[1].read, isFalse);
    });

    test('throws BackendAuthException on a 401 response', () async {
      final client = MockClient((request) async => http.Response('', 401));

      final backend = KomgaBackend(_connectionInfo(), httpClient: client);

      expect(
          () => backend.getLibraries(), throwsA(isA<BackendAuthException>()));
    });
  });
}
