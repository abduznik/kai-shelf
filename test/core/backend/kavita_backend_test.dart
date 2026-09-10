import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/backend/auth_credentials.dart';
import 'package:kai_shelf/core/backend/kavita/kavita_backend.dart';
import 'package:kai_shelf/core/backend/models.dart';

ServerConnectionInfo _connectionInfo() {
  return ServerConnectionInfo(
    serverId: 'server-1',
    displayName: 'test',
    baseUrl: Uri.parse('http://example.com:5000'),
    type: BackendType.kavita,
  );
}

void main() {
  group('KavitaBackend.login', () {
    test('exchanges a valid API key for a bearer token', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/Plugin/authenticate') {
          expect(request.url.queryParameters['apiKey'], 'valid-key');
          expect(request.url.queryParameters['pluginName'], isNotNull);
          return http.Response(
            jsonEncode({
              'id': 1,
              'username': 'reader',
              'token': 'jwt-access-token',
              'refreshToken': 'jwt-refresh-token',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final backend = KavitaBackend(_connectionInfo(), httpClient: client);
      final result = await backend
          .login(const AuthCredentials.kavita(apiKey: 'valid-key'));

      expect(result.success, isTrue);
      expect(result.connectionInfo!.sessionToken, 'jwt-access-token');
      expect(result.connectionInfo!.refreshToken, 'jwt-refresh-token');
    });

    test('fails with an invalid API key', () async {
      final client = MockClient((request) async => http.Response('', 401));

      final backend = KavitaBackend(_connectionInfo(), httpClient: client);
      final result =
          await backend.login(const AuthCredentials.kavita(apiKey: 'bad-key'));

      expect(result.success, isFalse);
    });
  });

  group('KavitaBackend data fetches', () {
    test('getMangaList maps a plain series array', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/Series/v2') {
          return http.Response(
            jsonEncode([
              {'id': 1, 'name': 'Chainsaw Man', 'libraryId': 1},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final backend = KavitaBackend(_connectionInfo(), httpClient: client);
      final mangaList = await backend.getMangaList();

      expect(mangaList, hasLength(1));
      expect(mangaList.first.title, 'Chainsaw Man');
    });

    test(
        'getChapters flattens Series > Volumes > Chapters and caches read-progress context',
        () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/Series/1') {
          return http.Response(
            jsonEncode({'id': 1, 'name': 'Chainsaw Man', 'libraryId': 7}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/Series/metadata') {
          return http.Response('', 404);
        }
        if (request.url.path == '/api/Series/volumes') {
          return http.Response(
            jsonEncode([
              {
                'id': 10,
                'chapters': [
                  {'id': 100, 'number': '1', 'pages': 20, 'pagesRead': 20},
                  {'id': 101, 'number': '2', 'pages': 18, 'pagesRead': 0},
                ],
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final backend = KavitaBackend(_connectionInfo(), httpClient: client);
      final chapters = await backend.getChapters('1');

      expect(chapters, hasLength(2));
      expect(chapters[0].read, isTrue);
      expect(chapters[1].read, isFalse);

      // getPages relies on context cached during getChapters (Kavita has
      // no standalone "get chapter" endpoint to fall back on).
      final pages = await backend.getPages('100');
      expect(pages, hasLength(20));
      expect(pages.first.imageUrl, contains('chapterId=100'));
      expect(pages.first.imageUrl, contains('page=0'));
    });

    test('getPages throws a clear error if called before getChapters',
        () async {
      final client =
          MockClient((request) async => http.Response('not found', 404));
      final backend = KavitaBackend(_connectionInfo(), httpClient: client);

      expect(() => backend.getPages('unknown-chapter'),
          throwsA(isA<StateError>()));
    });
  });
}
