import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/backend/auth_credentials.dart';
import 'package:kai_shelf/core/backend/kavita/kavita_backend.dart';
import 'package:kai_shelf/core/backend/kavita/kavita_mappers.dart';
import 'package:kai_shelf/core/backend/komga/komga_backend.dart';
import 'package:kai_shelf/core/backend/komga/komga_mappers.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/suwayomi/suwayomi_backend.dart';
import 'package:kai_shelf/core/backend/suwayomi/suwayomi_mappers.dart';

ServerConnectionInfo _info(BackendType type) => ServerConnectionInfo(
      serverId: 's',
      displayName: 't',
      baseUrl: Uri.parse('http://example.com:1234'),
      type: type,
    );

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// The GraphQL client rejects responses without __typename.
dynamic _stamp(dynamic v) {
  if (v is Map) {
    return {
      for (final e in v.entries) e.key: _stamp(e.value),
      '__typename': 'T',
    };
  }
  if (v is List) return v.map(_stamp).toList();
  return v;
}

void main() {
  group('mappers', () {
    test('Suwayomi category keeps the default flag and count', () {
      final c = SuwayomiMappers.categoryFromJson({
        'id': 0,
        'name': 'Default',
        'isDefaultCategory': true,
        'mangas': {'totalCount': 4},
      });
      expect(
          (c.id, c.name, c.mangaCount, c.isDefault), ('0', 'Default', 4, true));
    });

    test('Suwayomi chapter reads isBookmarked', () {
      final c = SuwayomiMappers.chapterFromJson(
          {'id': 1, 'mangaId': 2, 'name': 'Ch', 'isBookmarked': true});
      expect(c.bookmarked, isTrue);
      expect(
          SuwayomiMappers.chapterFromJson({'id': 1, 'mangaId': 2, 'name': 'C'})
              .bookmarked,
          isFalse);
    });

    test('Komga collection counts its series', () {
      final c = KomgaMappers.categoryFromJson({
        'id': 'abc',
        'name': 'Reading',
        'seriesIds': ['a', 'b'],
      });
      expect((c.id, c.mangaCount), ('abc', 2));
    });

    test('Kavita collection uses title and itemCount', () {
      final c = KavitaMappers.categoryFromJson(
          {'id': 3, 'title': 'Faves', 'itemCount': 5});
      expect((c.id, c.name, c.mangaCount), ('3', 'Faves', 5));
    });
  });

  group('SuwayomiBackend categories', () {
    late List<Map<String, dynamic>> log;
    late SuwayomiBackend backend;
    var current = <int>[1];

    setUp(() {
      log = [];
      current = [1];
      backend = SuwayomiBackend(
        _info(BackendType.suwayomi),
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final q = body['query'] as String;
          final vars = (body['variables'] as Map?) ?? {};
          log.add({'q': q, 'v': vars});
          Map<String, dynamic> data;
          if (q.contains('query CategoryDetailList')) {
            data = {
              'categories': {
                'nodes': [
                  {
                    'id': 2,
                    'name': 'B',
                    'order': 2,
                    'isDefaultCategory': false,
                    'mangas': {'totalCount': 0}
                  },
                  {
                    'id': 0,
                    'name': 'Default',
                    'order': 0,
                    'isDefaultCategory': true,
                    'mangas': {'totalCount': 3}
                  },
                  {
                    'id': 1,
                    'name': 'A',
                    'order': 1,
                    'isDefaultCategory': false,
                    'mangas': {'totalCount': 1}
                  },
                ]
              }
            };
          } else if (q.contains('query MangaCategories')) {
            data = {
              'manga': {
                'categories': {
                  'nodes': [
                    for (final id in current) {'id': id}
                  ]
                }
              }
            };
          } else if (q.contains('mutation CreateCategory')) {
            data = {
              'createCategory': {
                'category': {
                  'id': 9,
                  'name': vars['name'],
                  'order': 3,
                  'isDefaultCategory': false
                }
              }
            };
          } else {
            data = {};
          }
          return http.Response(jsonEncode(_stamp({'data': data})), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
    });

    test('getCategories sorts by server order, default first', () async {
      final all = await backend.getCategories();
      expect(all.map((c) => c.name), ['Default', 'A', 'B']);
      expect(all.first.isDefault, isTrue);
    });

    test('setMangaCategories sends only the difference', () async {
      await backend.setMangaCategories('5', {'2', '3'});
      final m = log.last;
      expect(m['q'], contains('updateMangaCategories'));
      expect(m['v'], {
        'id': 5,
        'add': [2, 3],
        'remove': [1],
      });
    });

    test('setMangaCategories does nothing when unchanged', () async {
      await backend.setMangaCategories('5', {'1'});
      expect(
          log.where((e) => (e['q'] as String).contains('mutation')), isEmpty);
    });

    test('moveCategory offsets past the default category', () async {
      await backend.moveCategory('2', 0);
      expect(log.last['v'], {'id': 2, 'position': 1});
    });

    test('createCategory can file the first manga straight away', () async {
      final made = await backend.createCategory('New', firstMangaId: '5');
      expect(made.id, '9');
      expect(
          log
              .map((e) => e['q'] as String)
              .any((q) => q.contains('updateMangaCategories')),
          isTrue);
    });

    test('setChapterBookmarked sends isBookmarked', () async {
      await backend.setChapterBookmarked('7', true);
      expect(log.last['q'], contains('isBookmarked: \$bookmarked'));
      expect(log.last['v'], {'id': 7, 'bookmarked': true});
    });
  });

  group('KomgaBackend collections', () {
    late Map<String, List<String>> collections; // id -> series ids
    late List<String> calls;
    late KomgaBackend backend;

    setUp(() {
      collections = {
        'c1': ['s1'],
        'c2': ['s1', 's2'],
      };
      calls = [];
      backend = KomgaBackend(
        _info(BackendType.komga),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          calls.add('${request.method} $path');
          if (path == '/api/v1/collections' && request.method == 'GET') {
            return _json({
              'content': [
                for (final e in collections.entries)
                  {'id': e.key, 'name': e.key, 'seriesIds': e.value}
              ]
            });
          }
          if (path == '/api/v1/collections' && request.method == 'POST') {
            final b = jsonDecode(request.body) as Map<String, dynamic>;
            collections['new'] = (b['seriesIds'] as List).cast<String>();
            return _json(
                {'id': 'new', 'name': b['name'], 'seriesIds': b['seriesIds']});
          }
          if (path.startsWith('/api/v1/series/') &&
              path.endsWith('/collections')) {
            final sid = path.split('/')[4];
            return _json([
              for (final e in collections.entries)
                if (e.value.contains(sid)) {'id': e.key}
            ]);
          }
          final m = RegExp(r'^/api/v1/collections/(\w+)$').firstMatch(path);
          if (m != null) {
            final id = m.group(1)!;
            if (request.method == 'GET') {
              return _json({'id': id, 'seriesIds': collections[id]});
            }
            if (request.method == 'PATCH') {
              final b = jsonDecode(request.body) as Map<String, dynamic>;
              if (b['seriesIds'] != null) {
                final ids = (b['seriesIds'] as List).cast<String>();
                if (ids.isEmpty) {
                  return _json({
                    'violations': [
                      {'fieldName': 'seriesIds', 'message': 'must not be empty'}
                    ]
                  }, 400);
                }
                collections[id] = ids;
              }
              return http.Response('', 204);
            }
            if (request.method == 'DELETE') {
              collections.remove(id);
              return http.Response('', 204);
            }
          }
          return http.Response('nope', 404);
        }),
      );
    });

    test('lists collections with counts', () async {
      final all = await backend.getCategories();
      expect(all.map((c) => (c.id, c.mangaCount)), [('c1', 1), ('c2', 2)]);
    });

    test('refuses to create an empty collection', () async {
      expect(backend.canCreateEmptyCategory, isFalse);
      await expectLater(
          backend.createCategory('x'), throwsA(isA<BackendException>()));
      expect(calls, isEmpty);
    });

    test('creates with its first series', () async {
      final made = await backend.createCategory('x', firstMangaId: 's9');
      expect(collections['new'], ['s9']);
      expect(made.mangaCount, 1);
    });

    test('adding keeps the existing series, removing the last deletes',
        () async {
      await backend.setMangaCategories('s2', {'c1', 'c2'});
      expect(collections['c1'], ['s1', 's2']);

      await backend.setMangaCategories('s1', {});
      expect(collections.containsKey('c1'), isTrue);
      expect(collections['c1'], ['s2']);
      expect(collections['c2'], ['s2']);

      await backend.setMangaCategories('s2', {});
      expect(collections, isEmpty);
    });

    test('surfaces Komga validation messages', () async {
      final failing = KomgaBackend(
        _info(BackendType.komga),
        httpClient: MockClient((_) async => _json({
              'violations': [
                {'fieldName': 'name', 'message': 'must not be blank'}
              ]
            }, 400)),
      );
      await expectLater(
          failing.renameCategory('c1', ''),
          throwsA(isA<BackendException>()
              .having((e) => e.message, 'message', 'name must not be blank')));
    });
  });

  group('KavitaBackend collections', () {
    late List<Map<String, dynamic>> collections;
    late List<Map<String, dynamic>> posts;
    late KavitaBackend backend;

    Map<String, dynamic> coll(int id, String title) => {
          'id': id,
          'title': title,
          'summary': 'sum',
          'promoted': true,
          'itemCount': 0,
        };

    setUp(() {
      collections = [coll(1, 'One')];
      posts = [];
      backend = KavitaBackend(
        _info(BackendType.kavita),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/Collection' && request.method == 'GET') {
            expect(request.url.queryParameters['ownedOnly'], 'true');
            return _json(collections);
          }
          if (path == '/api/Collection' && request.method == 'DELETE') {
            collections.removeWhere((c) =>
                c['id'].toString() == request.url.queryParameters['tagId']);
            return http.Response('Collection deleted', 200);
          }
          if (path == '/api/Collection/all-series') {
            return _json([coll(1, 'One')]);
          }
          if (request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            posts.add({'path': path, ...body});
            if (path == '/api/Collection/update-for-series' &&
                body['collectionTagId'] == 0) {
              collections.add(coll(2, body['collectionTagTitle'] as String));
            }
            return http.Response('', 200);
          }
          return http.Response('nope', 404);
        }),
      );
    });

    test('creating finds the new collection by id difference', () async {
      expect(backend.canCreateEmptyCategory, isTrue);
      final made = await backend.createCategory('Two');
      expect((made.id, made.name), ('2', 'Two'));
      expect(posts.single['seriesIds'], isEmpty);
    });

    test('rename resends the summary and promoted flag', () async {
      await backend.renameCategory('1', 'Renamed');
      expect(posts.single, {
        'path': '/api/Collection/update',
        'id': 1,
        'title': 'Renamed',
        'summary': 'sum',
        'promoted': true,
      });
    });

    test('assign adds new collections and removes dropped ones', () async {
      collections.add(coll(2, 'Two'));
      await backend.setMangaCategories('7', {'2'});
      expect(posts.map((p) => p['path']), [
        '/api/Collection/update-for-series',
        '/api/Collection/update-series',
      ]);
      expect(posts[0]['collectionTagId'], 2);
      expect(posts[0]['seriesIds'], [7]);
      expect(posts[1]['seriesIdsToRemove'], [7]);
      expect((posts[1]['tag'] as Map)['id'], 1);
    });

    test('delete passes the tag id', () async {
      await backend.deleteCategory('1');
      expect(collections, isEmpty);
    });
  });
}
