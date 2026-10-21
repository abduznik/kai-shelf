import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/backend/auth_credentials.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/opds/opds_backend.dart';
import 'package:kai_shelf/core/backend/opds/opds_ids.dart';

import 'opds_fixtures.dart';

/// Routes keyed first by full URL (so query strings win) and then by path.
Map<String, String> baseRoutes() => {
      'https://library.example/api/v1/catalog/search?q=nixon%20papers':
          searchResultsFeedXml,
      'https://library.example/opds/all.xml?page=2': acquisitionFeedPage2Xml,
      'https://library.example/opds/browse?tag=nixon-richard':
          searchHitChildrenFeedXml,
      '/opds/root.xml': navRootFeedXml,
      '/opds/all.xml': acquisitionFeedXml,
      '/opds/popular.xml': acquisitionFeedXml,
      '/opds/opensearch.xml': openSearchDescriptionXml,
    };

({MockClient client, List<http.Request> requests}) serve(
    Map<String, String> routes) {
  final requests = <http.Request>[];
  final client = MockClient((request) async {
    requests.add(request);
    final body = routes[request.url.toString()] ?? routes[request.url.path];
    if (body == null) return http.Response('not found', 404);
    return http.Response(
      body,
      200,
      headers: {'content-type': 'application/atom+xml;profile=opds-catalog'},
    );
  });
  return (client: client, requests: requests);
}

ServerConnectionInfo connection(
        {Map<String, String> extraHeaders = const {}}) =>
    ServerConnectionInfo(
      serverId: 'opds-1',
      displayName: 'library.example',
      baseUrl: Uri.parse('$opdsBaseOrigin/opds/root.xml'),
      type: BackendType.opds,
      extraHeaders: extraHeaders,
    );

OpdsBackend backendFor(http.Client client, {ServerConnectionInfo? info}) =>
    OpdsBackend(info ?? connection(), client: client);

String? authorizationOf(http.Request request) =>
    request.headers['authorization'] ?? request.headers['Authorization'];

void main() {
  group('browsing', () {
    test('lists the root catalog\'s sub-catalogs as libraries', () async {
      final served = serve(baseRoutes());
      final backend = backendFor(served.client);

      final libraries = await backend.getLibraries();

      expect(
          libraries.map((l) => l.name), ['Popular Publications', 'All Books']);
      // A library id is the sub-catalog's absolute feed URL.
      expect(libraries.first.id, '$opdsBaseOrigin/opds/popular.xml');
      expect(libraries.last.id, '$opdsBaseOrigin/opds/all.xml');
    });

    test('a root catalog that is itself an acquisition feed is one library',
        () async {
      final served = serve({'/opds/root.xml': acquisitionFeedXml});
      final backend = backendFor(served.client);

      final libraries = await backend.getLibraries();

      expect(libraries.single.name, 'All Books');
      expect(libraries.single.id, '$opdsBaseOrigin/opds/root.xml');
    });

    test(
        'expands a navigation feed into one entry per book, without '
        'duplicates', () async {
      final served = serve(baseRoutes());
      final backend = backendFor(served.client);

      final books =
          await backend.getAllManga(libraryId: '$opdsBaseOrigin/opds/root.xml');

      // Both sub-catalogs resolve to the same canned acquisition feed, so
      // the same publication must not appear twice in the grid.
      expect(books.map((b) => b.title), ['Bob, Son of Bob', 'Second Book']);
      expect(
          served.requests.map((r) => r.url.path),
          containsAll(<String>[
            '/opds/popular.xml',
            '/opds/all.xml',
          ]));
    });

    test('maps book entries to titles with covers, authors and genres',
        () async {
      final served = serve(baseRoutes());
      final backend = backendFor(served.client);

      final books =
          await backend.getAllManga(libraryId: '$opdsBaseOrigin/opds/all.xml');
      final first = books.first;

      expect(first.title, 'Bob, Son of Bob');
      // Route-safe: it becomes a '/manga/:mangaId' path segment.
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(first.id), isTrue);
      expect(first.coverUrl, '$opdsBaseOrigin/covers/bob.png');
      expect(first.description, contains('Bob the Recursive'));
      expect(first.description, contains('son of Bob'));
      expect(first.genres, ["FICTION / Men's Adventure"]);
      expect(first.lastUpdated, isNotNull);
    });

    test('follows rel="next" when a later page is asked for', () async {
      final served = serve(baseRoutes());
      final backend = backendFor(served.client);

      final page2 = await backend.getMangaList(
          libraryId: '$opdsBaseOrigin/opds/all.xml', page: 1);
      expect(page2.single.title, 'Third Book');
      expect(served.requests.map((r) => r.url.toString()),
          contains('$opdsBaseOrigin/opds/all.xml?page=2'));

      final beyond = await backend.getMangaList(
          libraryId: '$opdsBaseOrigin/opds/all.xml', page: 2);
      expect(beyond, isEmpty);
    });
  });

  group('discovery', () {
    test('exposes the catalog as a single discoverable source', () async {
      final served = serve(baseRoutes());
      final backend = backendFor(served.client);

      final sources = await backend.getSources();

      expect(sources.single.name, 'Test Catalog Root');
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(sources.single.id), isTrue);
      expect(sources.single.contentWarning, ContentWarning.unknown);
      expect(await backend.getSourceFilters(sources.single.id), isEmpty);
      // OPDS is browse-only: these are deliberate no-ops, not errors.
      await backend.addToLibrary('whatever');
      await backend.removeFromLibrary('whatever');
    });

    test('browses the catalog feed', () async {
      final served = serve(baseRoutes());
      final backend = backendFor(served.client);

      final page = await backend.browseSource(OpdsBackend.sourceId);

      expect(
          page.items.map((m) => m.title), ['Bob, Son of Bob', 'Second Book']);
    });

    test('pages a source listing with rel="next"', () async {
      final served = serve({
        '/opds/root.xml': acquisitionFeedXml,
        '$opdsBaseOrigin/opds/all.xml?page=2': acquisitionFeedPage2Xml,
      });
      final backend = backendFor(served.client);

      final first = await backend.browseSource(OpdsBackend.sourceId, page: 1);
      expect(
          first.items.map((m) => m.title), ['Bob, Son of Bob', 'Second Book']);
      expect(first.hasNextPage, isTrue);

      final second = await backend.browseSource(OpdsBackend.sourceId, page: 2);
      expect(second.items.single.title, 'Third Book');
      expect(second.hasNextPage, isFalse);
    });
  });

  group('search', () {
    test('searches through the OpenSearch description and expands hits',
        () async {
      final served = serve(baseRoutes());
      final backend = backendFor(served.client);

      final page = await backend.browseSource(
        OpdsBackend.sourceId,
        mode: SourceBrowseMode.search,
        query: 'nixon papers',
        page: 1,
      );

      final urls = served.requests.map((r) => r.url.toString()).toList();
      // Hop 1: the root's `rel="search"` facet points at an OpenSearch
      // description document.
      expect(urls, contains('$opdsBaseOrigin/opds/opensearch.xml'));
      // Hop 2: the Atom Url template from that document, with the query
      // substituted and encoded.
      expect(
          urls,
          contains(
              'https://library.example/api/v1/catalog/search?q=nixon%20papers'));
      // The hit is a navigation entry, so it is expanded into the books it
      // points at instead of showing as an empty result.
      expect(page.items.map((m) => m.title),
          ['Nixon Papers 1969', 'Nixon Papers 1972']);
    });

    test('substitutes a templated search link directly', () async {
      final served = serve({
        '/opds/root.xml': templatedSearchFeedXml,
        '$opdsBaseOrigin/opds/search/secret%20history': acquisitionFeedXml,
      });
      final backend = backendFor(served.client);

      final page = await backend.browseSource(
        OpdsBackend.sourceId,
        mode: SourceBrowseMode.search,
        query: 'secret history',
        page: 1,
      );

      expect(served.requests.map((r) => r.url.toString()),
          contains('$opdsBaseOrigin/opds/search/secret%20history'));
      expect(page.items, isNotEmpty);
    });

    test('appends q= when the search link carries no template', () async {
      final served = serve({
        '/opds/root.xml': untemplatedSearchFeedXml,
        '$opdsBaseOrigin/opds/search?q=abc': acquisitionFeedXml,
      });
      final backend = backendFor(served.client);

      final page = await backend.browseSource(
        OpdsBackend.sourceId,
        mode: SourceBrowseMode.search,
        query: 'abc',
        page: 1,
      );

      expect(served.requests.map((r) => r.url.toString()),
          contains('$opdsBaseOrigin/opds/search?q=abc'));
      expect(page.items, isNotEmpty);
    });

    test('a catalog without a search facet fails with a clear error', () async {
      final served = serve({'/opds/root.xml': navRootFeedNoSearchXml});
      final backend = backendFor(served.client);

      await expectLater(
        backend.browseSource(
          OpdsBackend.sourceId,
          mode: SourceBrowseMode.search,
          query: 'anything',
          page: 1,
        ),
        throwsA(isA<BackendException>()),
      );
    });
  });

  group('acquisition', () {
    test('resolves a title to its detail, formats and download page list',
        () async {
      final served = serve(baseRoutes());
      final backend = backendFor(served.client);

      final books =
          await backend.getAllManga(libraryId: '$opdsBaseOrigin/opds/all.xml');
      final mangaId = books.first.id;

      final detail = await backend.getMangaDetail(mangaId);
      expect(detail.title, 'Bob, Son of Bob');
      expect(detail.description, contains('Bob the Recursive'));

      final chapters = await backend.getChapters(mangaId);
      expect(chapters.map((c) => c.title), ['EPUB', 'Mobipocket']);
      // Chapter ids are also route- and folder-safe.
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(chapters.first.id), isTrue);

      // The existing download queue consumes this: one "page" whose url is
      // the acquisition file itself.
      final pages = await backend.getPages(chapters.first.id);
      expect(pages.single.index, 0);
      expect(pages.single.imageUrl, '$opdsBaseOrigin/content/bob.epub');

      // And the same chapter can be handed to the platform instead.
      expect(backend.acquisitionUrlForChapter(chapters.first.id)?.toString(),
          '$opdsBaseOrigin/content/bob.epub');
      expect(backend.acquisitionUrlForChapter('nonsense'), isNull);
    });

    test('an entry id that is no longer in the catalog is an error', () async {
      final served = serve(baseRoutes());
      final backend = backendFor(served.client);
      final missing = encodeOpdsEntryRef(
          feedUrl: '$opdsBaseOrigin/opds/all.xml', entryKey: 'gone');

      await expectLater(
          backend.getMangaDetail(missing), throwsA(isA<BackendException>()));
    });

    test('updateReadProgress is a no-op: OPDS is browse-only', () async {
      final served = serve(baseRoutes());
      final backend = backendFor(served.client);

      await backend.updateReadProgress('chapter', read: true);

      expect(served.requests, isEmpty);
    });
  });

  group('auth', () {
    test('sends the stored credentials with every request and every cover',
        () async {
      final headers = {'Authorization': 'Basic dXNlcjpwYXNz'};
      final served = serve(baseRoutes());
      final backend =
          backendFor(served.client, info: connection(extraHeaders: headers));

      final books =
          await backend.getAllManga(libraryId: '$opdsBaseOrigin/opds/all.xml');

      expect(served.requests, isNotEmpty);
      expect(
          served.requests
              .every((r) => authorizationOf(r) == 'Basic dXNlcjpwYXNz'),
          isTrue);
      expect(books.first.coverHeaders, headers);
    });

    test('login stores HTTP Basic credentials on the connection', () async {
      final served = serve(baseRoutes());
      final backend = backendFor(served.client, info: connection());

      final result = await backend.login(
          const AuthCredentials.opds(username: 'user', password: 'p@ss'));

      expect(result.success, isTrue);
      expect(
        result.connectionInfo!.extraHeaders['Authorization'],
        'Basic ${base64Encode(utf8.encode('user:p@ss'))}',
      );
    });

    test('login against a 401 catalog reports the auth requirement', () async {
      final client = MockClient((request) async => http.Response(
          'auth required', 401,
          headers: {'content-type': 'text/plain'}));
      final backend = backendFor(client);

      final result = await backend.login(const AuthCredentials.opds());

      expect(result.success, isFalse);
      expect(result.error, contains('401'));
    });

    test('login against a URL that is not an OPDS catalog says so', () async {
      final client = MockClient((request) async =>
          http.Response(htmlPage, 200, headers: {'content-type': 'text/html'}));
      final backend = backendFor(client);

      final result = await backend.login(const AuthCredentials.opds());

      expect(result.success, isFalse);
      expect(result.error, contains('OPDS'));
    });
  });
}
