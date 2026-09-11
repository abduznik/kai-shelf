import 'dart:convert';

import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;

import '../auth_credentials.dart';
import '../models.dart';
import '../server_backend.dart';
import 'suwayomi_mappers.dart';
import 'suwayomi_queries.dart';

/// Suwayomi (Tachidesk) adapter — talks to a single GraphQL endpoint.
///
/// Auth is HTTP Basic (server.authMode = BASIC_AUTH), sent on every
/// request. This is deliberate, not a fallback: Suwayomi's other auth
/// modes (SIMPLE_LOGIN/UI_LOGIN) mint short-lived JWTs tied to cookie-based
/// sessions, which don't survive a stateless API client making independent
/// requests — confirmed against a real server, where a token obtained from
/// the login mutation was rejected as Unauthorized on the very next
/// request. BASIC_AUTH has no session/expiry to manage and is the only
/// mode Kai-Shelf supports.
class SuwayomiBackend implements ServerBackend, SourceCapableBackend {
  SuwayomiBackend(ServerConnectionInfo connectionInfo,
      {http.Client? httpClient})
      : _connectionInfo = connectionInfo,
        _httpClient = httpClient {
    _client = _buildClient(connectionInfo);
  }

  ServerConnectionInfo _connectionInfo;

  /// Injected only by tests, to route GraphQL requests through a
  /// [MockClient] instead of a real network call.
  final http.Client? _httpClient;
  late GraphQLClient _client;

  @override
  BackendType get type => BackendType.suwayomi;

  @override
  ServerConnectionInfo get connectionInfo => _connectionInfo;

  GraphQLClient _buildClient(ServerConnectionInfo info) {
    final httpLink = HttpLink(
      info.baseUrl.replace(path: '/api/graphql').toString(),
      defaultHeaders: info.extraHeaders,
      httpClient: _httpClient,
    );
    return GraphQLClient(link: httpLink, cache: GraphQLCache());
  }

  @override
  Future<AuthResult> login(AuthCredentials credentials) async {
    if (credentials is! SuwayomiCredentials) {
      return const AuthResult.failure(
          'Suwayomi backend received non-Suwayomi credentials');
    }

    final hasUsername =
        credentials.username != null && credentials.username!.isNotEmpty;
    final hasPassword =
        credentials.password != null && credentials.password!.isNotEmpty;

    final headers = <String, String>{};
    if (hasUsername && hasPassword) {
      final basicAuth = base64Encode(
          utf8.encode('${credentials.username}:${credentials.password}'));
      headers['Authorization'] = 'Basic $basicAuth';
    }
    // If only one of username/password is set, or neither, connect with no
    // auth header — the validation query below will correctly reject that
    // if the server actually requires BASIC_AUTH.

    final candidate = _connectionInfo.copyWith(extraHeaders: headers);
    _client = _buildClient(candidate);

    // categories is @requireAuth-gated, unlike aboutServer, so this
    // actually proves the credentials (or lack thereof) work — aboutServer
    // would "succeed" even on a server that requires auth.
    final result = await _client.query(
      QueryOptions(
        document: gql(SuwayomiQueries.categoryListQuery),
        fetchPolicy: FetchPolicy.noCache,
      ),
    );

    if (result.hasException) {
      if (headers.isEmpty) {
        return const AuthResult.failure(
            'This server requires a username and password.');
      }
      return const AuthResult.failure('Incorrect username or password.');
    }

    final updated = candidate;
    _client = _buildClient(updated);
    _connectionInfo = updated;
    return AuthResult.success(updated);
  }

  @override
  Future<void> logout() async {
    _connectionInfo = _connectionInfo.copyWith(extraHeaders: const {});
    _client = _buildClient(_connectionInfo);
  }

  @override
  Future<bool> validateSession() async {
    final result = await _client.query(
      QueryOptions(
          document: gql(SuwayomiQueries.aboutQuery),
          fetchPolicy: FetchPolicy.noCache),
    );
    return !result.hasException;
  }

  @override
  Future<List<KsLibrary>> getLibraries() async {
    final result = await _client.query(
      QueryOptions(
          document: gql(SuwayomiQueries.categoryListQuery),
          fetchPolicy: FetchPolicy.networkOnly),
    );
    _throwIfAuthError(result);

    final nodes = result.data?['categories']?['nodes'] as List? ?? [];
    return nodes
        .map((n) => SuwayomiMappers.libraryFromJson(n as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<KsManga>> getMangaList(
      {String? libraryId, String? searchQuery, int page = 0}) async {
    // Category-scoped listing has to go through category(id:).mangas — see
    // the doc comment on categoryMangaListQuery for why the manga-level
    // categoryId filter can't be used here.
    if (libraryId != null) {
      final result = await _client.query(
        QueryOptions(
          document: gql(SuwayomiQueries.categoryMangaListQuery),
          variables: {'categoryId': int.parse(libraryId)},
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      _throwIfAuthError(result);

      final nodes =
          result.data?['category']?['mangas']?['nodes'] as List? ?? [];
      final mangaList = nodes
          .map((n) => SuwayomiMappers.mangaFromJson(
                n as Map<String, dynamic>,
                buildImageUrl: buildImageUrl,
                coverHeaders: _connectionInfo.extraHeaders.isEmpty
                    ? null
                    : _connectionInfo.extraHeaders,
              ))
          .toList();

      if (searchQuery == null || searchQuery.isEmpty) return mangaList;
      final needle = searchQuery.toLowerCase();
      return mangaList
          .where((m) => m.title.toLowerCase().contains(needle))
          .toList();
    }

    final result = await _client.query(
      QueryOptions(
        document: gql(SuwayomiQueries.mangaListQuery),
        variables: {'searchQuery': searchQuery},
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    _throwIfAuthError(result);

    final nodes = result.data?['mangas']?['nodes'] as List? ?? [];
    return nodes
        .map((n) => SuwayomiMappers.mangaFromJson(
              n as Map<String, dynamic>,
              buildImageUrl: buildImageUrl,
              coverHeaders: _connectionInfo.extraHeaders.isEmpty
                  ? null
                  : _connectionInfo.extraHeaders,
            ))
        .toList();
  }

  @override
  Future<KsManga> getMangaDetail(String mangaId) async {
    final result = await _client.query(
      QueryOptions(
        document: gql(SuwayomiQueries.mangaDetailQuery),
        variables: {'id': int.parse(mangaId)},
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    _throwIfAuthError(result);
    return SuwayomiMappers.mangaFromJson(
      result.data!['manga'] as Map<String, dynamic>,
      buildImageUrl: buildImageUrl,
      coverHeaders: _connectionInfo.extraHeaders.isEmpty
          ? null
          : _connectionInfo.extraHeaders,
    );
  }

  @override
  Future<List<KsChapter>> getChapters(String mangaId) async {
    final result = await _client.query(
      QueryOptions(
        document: gql(SuwayomiQueries.chapterListQuery),
        variables: {'mangaId': int.parse(mangaId)},
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    _throwIfAuthError(result);

    final nodes = result.data?['chapters']?['nodes'] as List? ?? [];
    return nodes
        .map((n) => SuwayomiMappers.chapterFromJson(n as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<KsPage>> getPages(String chapterId) async {
    // Suwayomi fetches pages lazily; this mutation both triggers that
    // fetch and returns the correct page paths directly, so there's no
    // need to (and, per the doc comment on the query, no reliable way to)
    // build page URLs by hand from mangaId/chapter-number.
    final result = await _client.mutate(
      MutationOptions(
        document: gql(SuwayomiQueries.fetchChapterPagesMutation),
        variables: {'chapterId': int.parse(chapterId)},
        fetchPolicy: FetchPolicy.noCache,
      ),
    );
    _throwIfAuthError(result);

    final pagePaths =
        result.data?['fetchChapterPages']?['pages'] as List? ?? [];
    return List.generate(
      pagePaths.length,
      (i) => KsPage(
        index: i,
        imageUrl: buildImageUrl(pagePaths[i] as String).toString(),
        extraHeaders: _connectionInfo.extraHeaders.isEmpty
            ? null
            : _connectionInfo.extraHeaders,
      ),
    );
  }

  @override
  Future<void> updateReadProgress(String chapterId,
      {required bool read, double? lastPageRead}) async {
    final result = await _client.mutate(
      MutationOptions(
        document: gql(SuwayomiQueries.updateChapterMutation),
        variables: {
          'id': int.parse(chapterId),
          'isRead': read,
          'lastPageRead': lastPageRead?.round(),
        },
        fetchPolicy: FetchPolicy.noCache,
      ),
    );
    _throwIfAuthError(result);
  }

  @override
  Future<List<KsSource>> getSources() async {
    final result = await _client.query(
      QueryOptions(
          document: gql(SuwayomiQueries.sourceListQuery),
          fetchPolicy: FetchPolicy.networkOnly),
    );
    _throwIfAuthError(result);

    final nodes = result.data?['sources']?['nodes'] as List? ?? [];
    return nodes
        .map((n) => SuwayomiMappers.sourceFromJson(n as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<KsSourceManga>> searchSource(String sourceId, String query,
      {int page = 0}) async {
    final result = await _client.query(
      QueryOptions(
        document: gql(SuwayomiQueries.sourceSearchQuery),
        variables: {
          'sourceId': sourceId,
          'searchQuery': query,
          'page': page,
        },
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    _throwIfAuthError(result);

    final nodes = result.data?['fetchSourceManga']?['mangas'] as List? ?? [];
    return nodes
        .map((n) => SuwayomiMappers.sourceMangaFromJson(
              n as Map<String, dynamic>,
              buildImageUrl: buildImageUrl,
              coverHeaders: _connectionInfo.extraHeaders.isEmpty
                  ? null
                  : _connectionInfo.extraHeaders,
            ))
        .toList();
  }

  @override
  Future<void> addToLibrary(String sourceMangaId) async {
    final result = await _client.mutate(
      MutationOptions(
        document: gql(SuwayomiQueries.addMangaToLibraryMutation),
        variables: {'id': int.parse(sourceMangaId)},
        fetchPolicy: FetchPolicy.noCache,
      ),
    );
    _throwIfAuthError(result);
  }

  @override
  Uri buildImageUrl(String pathOrId) {
    if (pathOrId.startsWith('http')) return Uri.parse(pathOrId);
    return _connectionInfo.baseUrl.replace(path: pathOrId);
  }

  void _throwIfAuthError(QueryResult result) {
    if (!result.hasException) return;
    final message = result.exception.toString();
    if (message.contains('401') || message.contains('Unauthorized')) {
      throw const BackendAuthException();
    }
  }
}
