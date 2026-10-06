import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/suwayomi/suwayomi_backend.dart';
import 'package:kai_shelf/core/backend/suwayomi/suwayomi_mappers.dart';

/// The GraphQL client adds __typename to every selection set and rejects
/// responses without it, so the mock stamps it onto every object.
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

typedef _Handler = Map<String, dynamic> Function(
    String query, Map<String, dynamic> variables);

SuwayomiBackend _backend(_Handler handler, {List<Map<String, dynamic>>? log}) {
  final client = MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final vars = (body['variables'] as Map?)?.cast<String, dynamic>() ?? {};
    log?.add({'query': body['query'], 'variables': vars});
    return http.Response(
      jsonEncode(_stamp(handler(body['query'] as String, vars))),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return SuwayomiBackend(
    ServerConnectionInfo(
      serverId: 's',
      displayName: 't',
      baseUrl: Uri.parse('http://example.com:4567'),
      type: BackendType.suwayomi,
    ),
    httpClient: client,
  );
}

void main() {
  test('getExtensions maps fields and resolves icon URLs', () async {
    final backend = _backend((q, v) => {
          'data': {
            'extensions': {
              'nodes': [
                {
                  'pkgName': 'x.dex',
                  'name': 'MangaDex',
                  'lang': 'all',
                  'versionName': '1.4',
                  'iconUrl': '/api/v1/extension/icon/x.dex',
                  'isInstalled': true,
                  'hasUpdate': true,
                  'isObsolete': false,
                  'contentWarning': 'MIXED',
                  'extensionStore': {'name': 'Keiyoushi'},
                }
              ]
            }
          }
        });
    final ext = (await backend.getExtensions()).single;
    expect(ext.pkgName, 'x.dex');
    expect(ext.isInstalled, isTrue);
    expect(ext.hasUpdate, isTrue);
    expect(ext.contentWarning, ContentWarning.mixed);
    expect(ext.storeName, 'Keiyoushi');
    expect(ext.iconUrl, 'http://example.com:4567/api/v1/extension/icon/x.dex');
  });

  test('refresh uses fetchExtensions mutation', () async {
    final log = <Map<String, dynamic>>[];
    final backend = _backend((q, v) {
      return {
        'data': {
          'fetchExtensions': {'extensions': []}
        }
      };
    }, log: log);
    await backend.getExtensions(refresh: true);
    expect(log.single['query'], contains('fetchExtensions'));
  });

  test('install / update / uninstall send the right patch', () async {
    final log = <Map<String, dynamic>>[];
    final backend = _backend(
        (q, v) => {
              'data': {
                'updateExtension': {
                  'extension': {'pkgName': 'x', 'isInstalled': true}
                }
              }
            },
        log: log);
    await backend.installExtension('x');
    await backend.updateExtension('x');
    await backend.uninstallExtension('x');
    expect(log.map((l) => l['variables']['patch']), [
      {'install': true},
      {'update': true},
      {'uninstall': true},
    ]);
    expect(log.first['variables']['id'], 'x');
  });

  test('server errors surface as BackendException', () async {
    final backend = _backend((q, v) => {
          'errors': [
            {'message': 'Download failed'}
          ]
        });
    expect(backend.installExtension('x'), throwsA(isA<Exception>()));
  });

  test('repos can be listed, added and removed', () async {
    final log = <Map<String, dynamic>>[];
    final backend = _backend((q, v) {
      if (q.contains('extensionStores')) {
        return {
          'data': {
            'extensionStores': {
              'nodes': [
                {'name': 'Keiyoushi', 'indexUrl': 'https://k/index.json'}
              ]
            }
          }
        };
      }
      return {
        'data': {'ok': {}}
      };
    }, log: log);
    final repos = await backend.getExtensionRepos();
    expect(repos.single.name, 'Keiyoushi');
    await backend.addExtensionRepo('https://r/index.json');
    await backend.removeExtensionRepo('https://r/index.json');
    expect(log[1]['variables'], {'indexUrl': 'https://r/index.json'});
    expect(log[2]['query'], contains('removeExtensionStore'));
  });

  test('browseSource sends type, query, page and nested filter changes',
      () async {
    final log = <Map<String, dynamic>>[];
    final backend = _backend(
        (q, v) => {
              'data': {
                'fetchSourceManga': {
                  'hasNextPage': true,
                  'mangas': [
                    {
                      'id': 7,
                      'title': 'Found',
                      'thumbnailUrl': '/api/v1/manga/7/thumbnail',
                      'inLibrary': false,
                    }
                  ]
                }
              }
            },
        log: log);
    final page = await backend.browseSource(
      '42',
      mode: SourceBrowseMode.search,
      query: 'berserk',
      page: 2,
      filters: const [
        KsFilterChange(path: [3, 1], triState: KsTriState.exclude),
        KsFilterChange(path: [5], sortIndex: 2, sortAscending: true),
      ],
    );
    expect(page.hasNextPage, isTrue);
    expect(page.items.single.title, 'Found');
    final vars = log.single['variables'] as Map;
    expect(vars['type'], 'SEARCH');
    expect(vars['query'], 'berserk');
    expect(vars['page'], 2);
    expect(vars['filters'], [
      {
        'position': 3,
        'groupChange': {'position': 1, 'triState': 'EXCLUDE'}
      },
      {
        'position': 5,
        'sortState': {'index': 2, 'ascending': true}
      },
    ]);
  });

  test('popular browse sends no query or filters', () async {
    final log = <Map<String, dynamic>>[];
    final backend = _backend(
        (q, v) => {
              'data': {
                'fetchSourceManga': {'hasNextPage': false, 'mangas': []}
              }
            },
        log: log);
    await backend.browseSource('42', filters: const [
      KsFilterChange(path: [0], checkBox: true)
    ]);
    final vars = log.single['variables'] as Map;
    expect(vars['type'], 'POPULAR');
    expect(vars['query'], isNull);
    expect(vars['filters'], isNull);
  });

  test('filters map every kind, keeping raw positions', () {
    final filters = SuwayomiMappers.filtersFromJson([
      {'__typename': 'HeaderFilter', 'hName': 'Header'},
      {'__typename': 'CheckBoxFilter', 'cName': 'Check', 'checkDefault': true},
      {'__typename': 'SomethingNew'},
      {
        '__typename': 'GroupFilter',
        'gName': 'Genres',
        'groupFilters': [
          {
            '__typename': 'TriStateFilter',
            'triName': 'Action',
            'triDefault': 'INCLUDE'
          },
        ],
      },
      {
        '__typename': 'SortFilter',
        'sortName': 'Sort',
        'sortValues': ['A', 'B'],
        'sortDefault': {'index': 1, 'ascending': true},
      },
      {
        '__typename': 'SelectFilter',
        'selName': 'Sel',
        'selValues': ['x', 'y'],
        'selDefault': 1,
      },
      {'__typename': 'TextFilter', 'tName': 'Author', 'textDefault': 'z'},
    ]);
    expect(filters.map((f) => f.position), [0, 1, 3, 4, 5, 6]);
    expect((filters[1] as KsCheckBoxFilter).value, isTrue);
    final group = filters[2] as KsGroupFilter;
    expect(
        (group.children.single as KsTriStateFilter).value, KsTriState.include);
    expect((filters[3] as KsSortFilter).ascending, isTrue);
    expect((filters[4] as KsSelectFilter).selected, 1);
    expect((filters[5] as KsTextFilter).value, 'z');
  });

  test('chapters of a title not in the library are fetched from its source',
      () async {
    final log = <Map<String, dynamic>>[];
    final backend = _backend((q, v) {
      if (q.contains('fetchChapters')) {
        return {
          'data': {
            'fetchChapters': {
              'chapters': [
                {
                  'id': 5,
                  'mangaId': 9,
                  'name': 'Ch.1',
                  'chapterNumber': 1.0,
                  'isRead': false,
                }
              ]
            }
          }
        };
      }
      return {
        'data': {
          'chapters': {'nodes': []}
        }
      };
    }, log: log);

    final chapters = await backend.getChapters('9');
    expect(chapters.single.title, 'Ch.1');
    expect(
        log.map((l) => l['query'] as String).last, contains('fetchChapters'));
  });

  test(
      'a title with no stored details gets them fetched, and reports '
      'that it is not in the library', () async {
    final backend = _backend((q, v) {
      if (q.contains('fetchManga')) {
        return {
          'data': {
            'fetchManga': {
              'manga': {
                'id': 9,
                'title': 'One Piece',
                'description': 'Pirates.',
                'genre': ['Action'],
                'status': 'ONGOING',
                'inLibrary': false,
              }
            }
          }
        };
      }
      return {
        'data': {
          'manga': {
            'id': 9,
            'title': 'One Piece',
            'description': null,
            'genre': [],
            'status': 'UNKNOWN',
            'inLibrary': false,
          }
        }
      };
    });
    final manga = await backend.getMangaDetail('9');
    expect(manga.description, 'Pirates.');
    expect(manga.genres, ['Action']);
    expect(manga.inLibrary, isFalse);
  });

  test(
      'a title whose source has no chapters yields an empty list, not an error',
      () async {
    final backend = _backend((q, v) {
      if (q.contains('fetchChapters')) {
        return {
          'errors': [
            {
              'message':
                  'Exception while fetching data (/fetchChapters) : No chapters found'
            }
          ]
        };
      }
      return {
        'data': {
          'chapters': {'nodes': []}
        }
      };
    });
    expect(await backend.getChapters('9'), isEmpty);
  });
}
