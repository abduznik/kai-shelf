import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth_credentials.dart';
import '../models.dart';
import '../server_backend.dart';
import 'opds_ids.dart';
import 'opds_models.dart';
import 'opds_parser.dart';

/// Read-only backend for OPDS 1.2 catalogs (issue #11): public library
/// catalogs, Standard Ebooks, Calibre-Web's `/opds` endpoint and friends.
///
/// OPDS is browse/download only by spec — there are no library writes — so
/// [updateReadProgress], [addToLibrary] and [removeFromLibrary] are
/// deliberate no-ops, and the write-shaped capabilities (categories,
/// bookmarks, extensions) are simply not implemented.
///
/// How the Atom document model maps onto the app's manga-shaped DTOs:
///  * `getLibraries` reports the root catalog's sub-catalogs, so the
///    library screen's chips become the catalog's own categories;
///  * one Atom entry with acquisition links becomes one [KsManga]; navigation
///    entries (pointers to other feeds) are expanded by fetching them,
///    because real catalogs nest root → subject → subtopic and the app's
///    cover grid has no drill-down level;
///  * an entry's acquisition links become [KsChapter]s, and `getPages` hands
///    the acquisition file itself to the existing download queue, while
///    [acquisitionUrlForChapter] hands the same file to the platform
///    handler instead (reading an EPUB in-app is out of scope).
class OpdsBackend
    implements
        ServerBackend,
        SourceCapableBackend,
        AcquisitionOpenCapableBackend {
  OpdsBackend(this.connectionInfo, {http.Client? client})
      : _client = client ?? http.Client(),
        _headers = Map<String, String>.of(connectionInfo.extraHeaders);

  @override
  final ServerConnectionInfo connectionInfo;

  /// The one source an OPDS connection exposes to the Discover screens. It
  /// also lands in a `'/discover/:sourceId'` path segment, so it must be
  /// route-safe — and since a connection carries exactly one catalog (the
  /// connection's own base URL), a constant is the whole story.
  static const String sourceId = 'opds-catalog';

  /// How deep navigation-only feeds are flattened into the cover grid.
  /// Standard Ebooks is root → genre → subgenre; the Office of the Historian
  /// catalog's search results are two navigation hops deep.
  static const int _maxNavigationDepth = 2;

  /// Upper bound on child-feed fetches per listing, so a huge catalog can
  /// never turn one grid load into hundreds of requests.
  static const int _maxExpansionRequests = 8;

  /// Upper bound on entries flattened into a single listing.
  static const int _maxExpandedEntries = 200;

  final http.Client _client;
  Map<String, String> _headers;

  /// OpenSearch description documents rarely change and cost an extra
  /// request each, so their resolved templates are remembered per session.
  final Map<Uri, String?> _searchTemplates = {};

  Uri get _root => connectionInfo.baseUrl;

  /// Auth headers for covers, downloads and feeds; null when there are none,
  /// so public catalogs stay header-free.
  Map<String, String>? get _authHeadersOrNull =>
      _headers.isEmpty ? null : _headers;

  @override
  BackendType get type => BackendType.opds;

  // ---------------------------------------------------------------- session

  /// OPDS has no session: connecting is "does an OPDS catalog answer at that
  /// URL?". The optional credentials are HTTP Basic, which is how
  /// Calibre-Web and self-hosted library catalogs gate their feeds.
  @override
  Future<AuthResult> login(AuthCredentials credentials) async {
    var headers = <String, String>{};
    if (credentials is OpdsCredentials &&
        (credentials.username ?? '').isNotEmpty) {
      final token = base64Encode(
          utf8.encode('${credentials.username}:${credentials.password ?? ''}'));
      headers = {'Authorization': 'Basic $token'};
    }
    _headers = headers;
    try {
      final result = await _fetch(_root);
      if (result.status == 401) {
        return const AuthResult.failure(
            'That catalog requires a username and password (HTTP 401).');
      }
      if (result.status != 200) {
        return AuthResult.failure(
            'The catalog answered HTTP ${result.status} instead of a feed.');
      }
      if (!looksLikeOpdsCatalog(result.body)) {
        return const AuthResult.failure(
            'No OPDS catalog was found at that URL — an Atom feed with OPDS '
            'catalog relations was expected.');
      }
      return AuthResult.success(connectionInfo.copyWith(extraHeaders: headers));
    } catch (error) {
      return AuthResult.failure('Could not reach the catalog: $error');
    }
  }

  @override
  Future<void> logout() async {}

  @override
  Future<bool> validateSession() async {
    try {
      final result = await _fetch(_root);
      return result.status == 200 && looksLikeOpdsCatalog(result.body);
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- browsing

  /// The root catalog's sub-catalogs, one chip each on the library screen. A
  /// catalog that is a single acquisition feed has no sub-catalogs and
  /// becomes one "library" holding itself.
  @override
  Future<List<KsLibrary>> getLibraries() async {
    final feed = await _fetchFeed(_root);
    final subCatalogs = feed.subCatalogRefs;
    if (subCatalogs.isEmpty) {
      return [KsLibrary(id: _root.toString(), name: feed.title)];
    }
    return [
      for (final ref in subCatalogs)
        KsLibrary(
          id: ref.href.toString(),
          name: ref.title.isEmpty ? feed.title : ref.title,
        ),
    ];
  }

  @override
  Future<List<KsManga>> getMangaList({
    String? libraryId,
    String? searchQuery,
    int page = 0,
  }) async {
    final query = searchQuery?.trim() ?? '';
    if (query.isNotEmpty) {
      return (await _search(_feedUri(libraryId), query, page: page)).items;
    }
    var url = _feedUri(libraryId);
    for (var i = 0; i < page; i++) {
      final next = (await _fetchFeed(url)).nextHref;
      if (next == null) return [];
      url = next;
    }
    final feed = await _fetchFeed(url);
    return _toMangaList(
        await _collectEntries(feed, url, _Budget(_maxExpansionRequests)), url);
  }

  /// OPDS has no cheap "count everything" call: [page] 0 is the catalog's
  /// first page (with navigation feeds flattened, bounded), and paging
  /// further is the Discover screen's job, where `rel="next"` is followed
  /// one page at a time.
  @override
  Future<List<KsManga>> getAllManga({
    String? libraryId,
    String? searchQuery,
  }) =>
      getMangaList(libraryId: libraryId, searchQuery: searchQuery);

  @override
  Future<KsManga> getMangaDetail(String mangaId) async {
    final resolved = await _entryFor(mangaId);
    return _toManga(resolved.entry, resolved.feedUrl, key: resolved.key);
  }

  /// Acquisition links as chapters: one "chapter" per downloadable format
  /// (EPUB, PDF, Mobipocket, ...), which is what OPDS actually offers
  /// instead of page sets.
  @override
  Future<List<KsChapter>> getChapters(String mangaId) async {
    final resolved = await _entryFor(mangaId);
    final formats = resolved.entry.acquisitionLinks;
    return [
      for (var i = 0; i < formats.length; i++)
        KsChapter(
          id: encodeOpdsAcquisition(formats[i].href.toString()),
          mangaId: mangaId,
          title: _formatLabel(formats[i]),
          chapterNumber: i.toDouble(),
          uploadDate: resolved.entry.updated,
        ),
    ];
  }

  /// A publication is a single file, not a page set — the download queue
  /// gets the acquisition file itself as its one "page".
  @override
  Future<List<KsPage>> getPages(String chapterId) async {
    return [
      KsPage(
        index: 0,
        imageUrl: decodeOpdsAcquisition(chapterId).toString(),
        extraHeaders: _authHeadersOrNull,
      ),
    ];
  }

  @override
  Uri? acquisitionUrlForChapter(String chapterId) {
    try {
      return decodeOpdsAcquisition(chapterId);
    } on FormatException {
      return null;
    }
  }

  /// No-op by design: OPDS has no notion of read state, and writing one
  /// anywhere would be a library-write operation the spec does not have.
  @override
  Future<void> updateReadProgress(
    String chapterId, {
    required bool read,
    double? lastPageRead,
  }) async {}

  @override
  Uri buildImageUrl(String pathOrId) => _root.resolve(pathOrId);

  // -------------------------------------------------------------- discovery

  @override
  Future<List<KsSource>> getSources() async {
    final feed = await _fetchFeed(_root);
    return [
      KsSource(
        id: sourceId,
        name: feed.title,
        displayName: feed.title,
        supportsLatest: true,
      ),
    ];
  }

  @override
  Future<KsSourcePage> browseSource(
    String sourceId, {
    SourceBrowseMode mode = SourceBrowseMode.popular,
    String query = '',
    int page = 1,
    List<KsFilterChange> filters = const [],
  }) async {
    final search = query.trim();
    if (mode == SourceBrowseMode.search && search.isNotEmpty) {
      final result = await _search(_root, search, page: page - 1);
      return KsSourcePage(
        items: _toSourceManga(result.items),
        hasNextPage: result.hasNextPage,
      );
    }
    var url = _root;
    for (var i = 1; i < page; i++) {
      final next = (await _fetchFeed(url)).nextHref;
      if (next == null) {
        return const KsSourcePage(items: [], hasNextPage: false);
      }
      url = next;
    }
    final feed = await _fetchFeed(url);
    final entries =
        await _collectEntries(feed, url, _Budget(_maxExpansionRequests));
    return KsSourcePage(
      items: _toSourceManga(_toMangaList(entries, url)),
      hasNextPage: feed.nextHref != null,
    );
  }

  @override
  Future<List<KsSourceManga>> searchSource(
    String sourceId,
    String query, {
    int page = 0,
  }) async {
    final result = await browseSource(
      sourceId,
      mode: SourceBrowseMode.search,
      query: query,
      page: page + 1,
    );
    return result.items;
  }

  /// OPDS filters are whatever the catalog's feeds already partition by, so
  /// there is nothing to narrow client-side.
  @override
  Future<List<KsSourceFilter>> getSourceFilters(String sourceId) async => [];

  /// No-op by design — see [updateReadProgress].
  @override
  Future<void> addToLibrary(String sourceMangaId) async {}

  /// No-op by design — see [updateReadProgress].
  @override
  Future<void> removeFromLibrary(String sourceMangaId) async {}

  // ------------------------------------------------------------------ search

  /// Runs the catalog's search facet and maps what comes back. A hit may be
  /// a book directly (Calibre-Web, Standard Ebooks) or another navigation
  /// hop (the Office of the Historian catalog returns author/keyword
  /// sub-catalogs), which [_collectEntries] flattens — though a catalog
  /// whose hit links do not actually resolve to books (that server ignores
  /// its own `?tag=` parameter) can still come back empty.
  Future<({List<KsManga> items, bool hasNextPage})> _search(
    Uri scope,
    String query, {
    int page = 0,
  }) async {
    var url = await _searchUrl(scope, query);
    for (var i = 0; i < page; i++) {
      final next = (await _fetchFeed(url)).nextHref;
      if (next == null) return (items: const <KsManga>[], hasNextPage: false);
      url = next;
    }
    final feed = await _fetchFeed(url);
    final entries =
        await _collectEntries(feed, url, _Budget(_maxExpansionRequests));
    return (
      items: _toMangaList(entries, url),
      hasNextPage: feed.nextHref != null,
    );
  }

  /// Builds the search request URL from the catalog's `rel="search"` facet.
  ///
  /// Three shapes exist in the wild, in increasing order of cooperation: an
  /// OpenSearch description document naming an Atom Url template (the
  /// Office of the Historian catalog), a link href that is itself a
  /// `{searchTerms}` template (Calibre-Web), and a bare link with no
  /// template at all, where the query goes into a `q` parameter.
  Future<Uri> _searchUrl(Uri scope, String query) async {
    var link = (await _fetchFeed(scope)).searchLink;
    link ??= (await _fetchFeed(_root)).searchLink;
    if (link == null) {
      throw const BackendException(
          'This catalog does not offer a search facet.');
    }
    final href = link.href.toString();
    final type = (link.type ?? '').toLowerCase();
    if (type.contains('opensearchdescription')) {
      final template = await _searchTemplate(link.href);
      if (template == null) {
        throw const BackendException(
            'The catalog\'s OpenSearch description has no Atom search '
            'template.');
      }
      return _expandSearchTerms(template, query);
    }
    if (_isSearchTemplate(href)) return _expandSearchTerms(href, query);
    return link.href
        .replace(queryParameters: {...link.href.queryParameters, 'q': query});
  }

  bool _isSearchTemplate(String href) =>
      href.contains('{searchTerms') || href.contains('%7BsearchTerms');

  Uri _expandSearchTerms(String template, String query) {
    // Percent-encoded rather than form-encoded: a `{searchTerms}` template
    // frequently sits in the *path* (`/opds/search/{searchTerms}`), where a
    // '+' would be a literal plus instead of a space.
    final encoded = Uri.encodeComponent(query);
    final expanded = template
        .replaceAll('{searchTerms}', encoded)
        .replaceAll('{searchTerms?}', encoded)
        // Uri.resolve percent-encodes the braces, so accept the encoded
        // spelling too — confirmed with a real `dart` probe.
        .replaceAll('%7BsearchTerms%7D', encoded)
        .replaceAll('%7BsearchTerms%3F%7D', encoded);
    return Uri.parse(expanded);
  }

  Future<String?> _searchTemplate(Uri descriptionUrl) async {
    if (_searchTemplates.containsKey(descriptionUrl)) {
      return _searchTemplates[descriptionUrl];
    }
    String? template;
    try {
      final result = await _fetch(descriptionUrl);
      if (result.status == 200) {
        template = parseOpensearchAtomTemplate(result.body);
      }
    } catch (_) {
      // An unreachable description means "cannot search", not "network
      // error" — the caller surfaces the clearer message.
    }
    _searchTemplates[descriptionUrl] = template;
    return template;
  }

  // ------------------------------------------------------------------ feeds

  /// Book entries of [feed], with navigation-only feeds flattened by
  /// fetching the sub-catalogs they point at. Bounded by depth, request count
  /// and entry count ([budget] is shared across the whole walk).
  Future<List<OpdsEntry>> _collectEntries(
    OpdsFeed feed,
    Uri feedUrl,
    _Budget budget, {
    int depth = 0,
  }) async {
    final books = [
      for (final entry in feed.entries)
        if (entry.acquisitionLinks.isNotEmpty) entry,
    ];
    if (books.isNotEmpty || depth >= _maxNavigationDepth) return books;

    final collected = <OpdsEntry>[];
    final seen = <String>{};
    for (final ref in feed.subCatalogRefs) {
      if (!budget.claim()) break;
      final OpdsFeed child;
      try {
        child = await _fetchFeed(ref.href);
      } catch (_) {
        continue; // one unreachable sub-catalog must not sink the listing
      }
      for (final entry
          in await _collectEntries(child, ref.href, budget, depth: depth + 1)) {
        if (entry.id.isNotEmpty && !seen.add(entry.id)) continue;
        collected.add(entry);
      }
      if (collected.length >= _maxExpandedEntries) break;
    }
    return collected.take(_maxExpandedEntries).toList();
  }

  Future<OpdsFeed> _fetchFeed(Uri url) async {
    final result = await _fetch(url);
    if (result.status == 401) throw const BackendAuthException();
    if (result.status != 200) {
      throw BackendException(
          'The catalog at $url answered HTTP ${result.status}.');
    }
    // Resolve relative links against the URL that actually answered (the
    // request may have been redirected).
    return parseOpdsCatalog(result.body, feedUrl: result.url);
  }

  Future<({String body, int status, Uri url})> _fetch(Uri url) async {
    final request = http.Request('GET', url);
    request.headers.addAll(_headers);
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    // package:http's Response drops the post-redirect URL; send() exposes it,
    // which the feed parse and the stored connection both need.
    final finalUrl = streamed is http.BaseResponseWithUrl
        ? (streamed as http.BaseResponseWithUrl).url
        : url;
    return (body: response.body, status: response.statusCode, url: finalUrl);
  }

  Uri _feedUri(String? libraryId) {
    if (libraryId == null || libraryId.trim().isEmpty) return _root;
    final trimmed = libraryId.trim();
    if (Uri.tryParse(trimmed) == null) return _root;
    try {
      return _root.resolve(trimmed);
    } on FormatException {
      return _root;
    }
  }

  // ---------------------------------------------------------------- mapping

  Future<({OpdsEntry entry, Uri feedUrl, String key})> _entryFor(
      String mangaId) async {
    final (feedUrl: feedUrl, entryKey: entryKey) = decodeOpdsEntryRef(mangaId);
    final url = Uri.parse(feedUrl);
    final feed = await _fetchFeed(url);
    final fallbackIndex =
        entryKey.startsWith('#') ? int.tryParse(entryKey.substring(1)) : null;
    for (var i = 0; i < feed.entries.length; i++) {
      final entry = feed.entries[i];
      if (entry.id == entryKey ||
          (fallbackIndex != null && i == fallbackIndex)) {
        return (entry: entry, feedUrl: url, key: entryKey);
      }
    }
    throw BackendException('That title is no longer listed in the catalog.');
  }

  List<KsManga> _toMangaList(List<OpdsEntry> entries, Uri feedUrl) => [
        for (var i = 0; i < entries.length; i++)
          _toManga(
            entries[i],
            feedUrl,
            key: entries[i].id.isNotEmpty ? entries[i].id : '#$i',
          ),
      ];

  KsManga _toManga(OpdsEntry entry, Uri feedUrl, {required String key}) {
    return KsManga(
      id: encodeOpdsEntryRef(feedUrl: feedUrl.toString(), entryKey: key),
      title: entry.title,
      coverUrl: entry.coverLink?.href.toString(),
      coverHeaders: _authHeadersOrNull,
      description: _describe(entry),
      genres: entry.categories,
      lastUpdated: entry.updated,
      // OPDS is browse-only: there is no library membership to track, and
      // reporting false would show the "add to library" banner with a
      // button that cannot do anything.
      inLibrary: true,
    );
  }

  List<KsSourceManga> _toSourceManga(List<KsManga> mangas) => [
        for (final manga in mangas)
          KsSourceManga(
            id: manga.id,
            title: manga.title,
            coverUrl: manga.coverUrl,
            coverHeaders: manga.coverHeaders,
            description: manga.description,
            genres: manga.genres,
            inLibrary: manga.inLibrary,
          ),
      ];

  String? _describe(OpdsEntry entry) {
    final buffer = StringBuffer();
    if (entry.authors.isNotEmpty) {
      buffer.write('By ${entry.authors.join(', ')}');
    }
    final summary = entry.summary?.trim();
    if (summary != null && summary.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(summary);
    }
    return buffer.isEmpty ? null : buffer.toString();
  }

  String _formatLabel(OpdsLink link) {
    final title = link.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final type = (link.type ?? '').toLowerCase();
    if (type.contains('epub')) return 'EPUB';
    if (type.contains('pdf')) return 'PDF';
    if (type.contains('mobi')) return 'Mobipocket';
    if (type.contains('zip')) return 'ZIP';
    return type.isEmpty ? 'Download' : type;
  }

  void dispose() => _client.close();
}

/// Shared request budget for one navigation-flattening walk.
class _Budget {
  _Budget(this._remaining);

  int _remaining;

  bool claim() {
    if (_remaining <= 0) return false;
    _remaining--;
    return true;
  }
}
