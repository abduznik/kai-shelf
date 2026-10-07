import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/backend/kavita/kavita_backend.dart';
import 'package:kai_shelf/core/backend/komga/komga_backend.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/server_backend.dart';
import 'package:kai_shelf/core/backend/suwayomi/suwayomi_backend.dart';

ServerConnectionInfo _info(BackendType type) => ServerConnectionInfo(
      serverId: 's',
      displayName: 't',
      baseUrl: Uri.parse('http://example.com:8080'),
      type: type,
    );

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

void main() {
  test('all three adapters advertise the history capability', () {
    expect(SuwayomiBackend(_info(BackendType.suwayomi)),
        isA<HistoryCapableBackend>());
    expect(
        KomgaBackend(_info(BackendType.komga)), isA<HistoryCapableBackend>());
    expect(
        KavitaBackend(_info(BackendType.kavita)), isA<HistoryCapableBackend>());
  });

  group('Suwayomi', () {
    test('queries by lastReadAt desc and maps epoch-second timestamps',
        () async {
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({
          'data': {
            '__typename': 'Query',
            'chapters': {
              '__typename': 'ChapterNodeList',
              'nodes': [
                {
                  '__typename': 'ChapterType',
                  'id': 5,
                  'name': 'Vol 03',
                  'chapterNumber': 3.0,
                  'isRead': true,
                  'lastPageRead': 3,
                  'lastReadAt': '1791386179',
                  'pageCount': 4,
                  'manga': {
                    '__typename': 'MangaType',
                    'id': 2,
                    'title': 'Beta Quest',
                    'thumbnailUrl': '/api/v1/manga/2/thumbnail',
                  },
                },
                {
                  '__typename': 'ChapterType',
                  'id': 2,
                  'name': 'Vol 01',
                  'chapterNumber': 1.0,
                  'isRead': false,
                  'lastPageRead': 0,
                  'lastReadAt': '1791386177',
                  'pageCount': -1,
                  'manga': {
                    '__typename': 'MangaType',
                    'id': 1,
                    'title': 'Alpha Saga',
                    'thumbnailUrl': null
                  },
                },
              ],
            },
          },
        });
      });
      final backend =
          SuwayomiBackend(_info(BackendType.suwayomi), httpClient: client);

      final history = await backend.getHistory(limit: 10, offset: 20);

      expect(sent['variables'], {'first': 10, 'offset': 20});
      expect(sent['query'], contains('LAST_READ_AT'));
      expect(history, hasLength(2));
      expect(history[0].mangaTitle, 'Beta Quest');
      expect(history[0].chapterId, '5');
      expect(history[0].read, isTrue);
      expect(history[0].pageCount, 4);
      expect(history[0].coverUrl,
          'http://example.com:8080/api/v1/manga/2/thumbnail');
      expect(history[0].lastReadAt.millisecondsSinceEpoch, 1791386179 * 1000);
      // Pages not fetched yet (-1) and no cover both come through as null.
      expect(history[1].pageCount, isNull);
      expect(history[1].coverUrl, isNull);
    });
  });

  group('Komga', () {
    Map<String, dynamic> book(
            String id, String name, Map<String, dynamic>? rp) =>
        {
          'id': id,
          'seriesId': 'ser-$id',
          'seriesTitle': 'Series $id',
          'name': name,
          'number': 2,
          'media': {'pagesCount': 24},
          'readProgress': rp,
        };

    test('asks for read and in-progress books by progress time, desc',
        () async {
      late Uri requested;
      final client = MockClient((request) async {
        requested = request.url;
        return _json({
          'content': [
            book('b1', 'Vol 2', {
              'page': 6,
              'completed': false,
              'lastModified': '2026-10-07T15:16:54Z',
            }),
            book('b2', 'Vol 3', {
              'page': 24,
              'completed': true,
              'lastModified': '2026-10-07T15:16:55Z',
            }),
            book('b3', 'Vol 4', null),
          ],
        });
      });
      final backend =
          KomgaBackend(_info(BackendType.komga), httpClient: client);

      final history = await backend.getHistory(limit: 20, offset: 40);

      expect(requested.path, '/api/v1/books');
      expect(
          requested.queryParametersAll['read_status'], ['READ', 'IN_PROGRESS']);
      expect(
          requested.queryParameters['sort'], 'readProgress.lastModified,desc');
      expect(requested.queryParameters['size'], '20');
      expect(requested.queryParameters['page'], '2');

      // The book without progress is dropped.
      expect(history.map((e) => e.chapterId), ['b1', 'b2']);
      expect(history[0].mangaId, 'ser-b1');
      expect(history[0].mangaTitle, 'Series b1');
      expect(history[0].pageCount, 24);
      expect(history[0].lastPageRead, 6);
      expect(history[0].read, isFalse);
      expect(history[1].read, isTrue);
      expect(history[0].coverUrl,
          'http://example.com:8080/api/v1/series/ser-b1/thumbnail');
      expect(
          history[0].lastReadAt.toUtc(), DateTime.utc(2026, 10, 7, 15, 16, 54));
    });
  });

  group('Kavita', () {
    Map<String, dynamic> series(int id, String name, String latest) => {
          'id': id,
          'name': name,
          'latestReadDate': latest,
        };
    Map<String, dynamic> chapter(int id, int pagesRead, String progress) => {
          'id': id,
          'number': '-100000',
          'title': '-100000',
          'pages': 4,
          'pagesRead': pagesRead,
          'lastReadingProgressUtc': progress,
        };

    test('expands recently read series into chapters sorted by progress time',
        () async {
      final volumeRequests = <String>[];
      final client = MockClient((request) async {
        if (request.url.path == '/api/Series/v2') {
          return _json([
            series(1, 'Beta Quest', '2026-10-07T15:17:11.2150591'),
            series(2, 'Alpha Saga', '2026-10-07T15:17:08.5382173'),
            series(3, 'Never Read', '0001-01-01T00:00:00'),
          ]);
        }
        if (request.url.path == '/api/Series/volumes') {
          final id = request.url.queryParameters['seriesId']!;
          volumeRequests.add(id);
          return _json(id == '1'
              ? [
                  {
                    'number': 2,
                    'name': '2',
                    'chapters': [chapter(2, 3, '2026-10-07T15:17:09.8078908')],
                  },
                  {
                    'number': 3,
                    'name': '3',
                    'chapters': [chapter(1, 4, '2026-10-07T15:17:11.2150603')],
                  },
                  {
                    'number': 1,
                    'name': '1',
                    'chapters': [chapter(3, 0, '0001-01-01T00:00:00')],
                  },
                ]
              : [
                  {
                    'number': 1,
                    'name': '1',
                    'chapters': [chapter(6, 2, '2026-10-07T15:17:08.5382173')],
                  },
                ]);
        }
        return http.Response('nope', 404);
      });
      final backend =
          KavitaBackend(_info(BackendType.kavita), httpClient: client);

      final history = await backend.getHistory();

      // The never-read series is not expanded; the never-opened chapter is dropped.
      expect(volumeRequests.toSet(), {'1', '2'});
      expect(history.map((e) => e.chapterId), ['1', '2', '6']);
      expect(history[0].mangaTitle, 'Beta Quest');
      expect(history[0].chapterTitle, 'Volume 3');
      expect(history[0].read, isTrue);
      expect(history[1].read, isFalse);
      expect(history[1].lastPageRead, 3);
      expect(history[1].pageCount, 4);
      expect(history[0].coverUrl,
          'http://example.com:8080/api/Image/series-cover?seriesId=1');
      // Timestamps carry no zone suffix on the wire but are UTC.
      expect(history[2].lastReadAt.toUtc().hour, 15);
    });

    test('offset and limit page through the assembled list', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/Series/v2') {
          return _json([series(1, 'S', '2026-10-07T15:00:00')]);
        }
        return _json([
          {
            'number': 1,
            'name': '1',
            'chapters': [
              chapter(1, 1, '2026-10-07T15:00:01'),
              chapter(2, 1, '2026-10-07T15:00:02'),
              chapter(3, 1, '2026-10-07T15:00:03'),
            ],
          },
        ]);
      });
      final backend =
          KavitaBackend(_info(BackendType.kavita), httpClient: client);
      final page = await backend.getHistory(limit: 1, offset: 1);
      expect(page.map((e) => e.chapterId), ['2']);
    });
  });
}
