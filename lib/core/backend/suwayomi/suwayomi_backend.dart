import 'package:graphql/client.dart';
import 'package:http/http.dart' as http;

import '../auth_credentials.dart';
import '../models.dart';
import '../server_backend.dart';
import 'suwayomi_mappers.dart';
import 'suwayomi_queries.dart';

/// Suwayomi (Tachidesk) adapter — talks to a single GraphQL endpoint.
/// Auth is a `login(username, password)` mutation returning an access/
/// refresh JWT pair; the access token then rides as a Bearer header on
/// every subsequent request.
class SuwayomiBackend implements ServerBackend {
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

    // Some Suwayomi instances run with no auth configured at all; treat an
    // empty username/password as "connect without authenticating." Validate
    // against an @requireAuth-gated query (aboutServer is NOT gated, so it
    // can't be used to confirm this — it would "succeed" even on servers
    // that do require a login).
    if ((credentials.username == null || credentials.username!.isEmpty) &&
        (credentials.password == null || credentials.password!.isEmpty)) {
      final unauthenticated = _connectionInfo.copyWith(extraHeaders: const {});
      _client = _buildClient(unauthenticated);
      final result = await _client.query(
        QueryOptions(
          document: gql(SuwayomiQueries.categoryListQuery),
          fetchPolicy: FetchPolicy.noCache,
        ),
      );
      if (result.hasException) {
        return const AuthResult.failure(
            'This server requires a username and password.');
      }
      _connectionInfo = unauthenticated;
      return AuthResult.success(unauthenticated);
    }

    final result = await _client.mutate(
      MutationOptions(
        document: gql(SuwayomiQueries.loginMutation),
        variables: {
          'username': credentials.username ?? '',
          'password': credentials.password ?? '',
        },
        fetchPolicy: FetchPolicy.noCache,
      ),
    );

    if (result.hasException) {
      return AuthResult.failure(_exceptionMessage(result.exception));
    }

    final payload = result.data?['login'] as Map<String, dynamic>?;
    final accessToken = payload?['accessToken'] as String?;
    final refreshToken = payload?['refreshToken'] as String?;
    if (accessToken == null) {
      return const AuthResult.failure('Server did not return an access token');
    }

    final updated = _connectionInfo.copyWith(
      sessionToken: accessToken,
      refreshToken: refreshToken,
      extraHeaders: {'Authorization': 'Bearer $accessToken'},
    );
    _client = _buildClient(updated);
    _connectionInfo = updated;
    return AuthResult.success(updated);
  }

  String _exceptionMessage(OperationException? exception) {
    if (exception == null) return 'Unknown error';
    final graphqlErrors = exception.graphqlErrors;
    if (graphqlErrors.isNotEmpty) {
      return graphqlErrors.map((e) => e.message).join('; ');
    }
    return exception.toString();
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
    final result = await _client.query(
      QueryOptions(
        document: gql(SuwayomiQueries.mangaListQuery),
        variables: {
          'categoryId': libraryId != null ? int.parse(libraryId) : null,
          'searchQuery': searchQuery,
        },
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    _throwIfAuthError(result);

    final nodes = result.data?['mangas']?['nodes'] as List? ?? [];
    return nodes
        .map((n) => SuwayomiMappers.mangaFromJson(n as Map<String, dynamic>))
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
        result.data!['manga'] as Map<String, dynamic>);
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
    final result = await _client.query(
      QueryOptions(
        document: gql(SuwayomiQueries.chapterPagesQuery),
        variables: {'id': int.parse(chapterId)},
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    _throwIfAuthError(result);

    final pageCount = result.data?['chapter']?['pageCount'] as int? ?? 0;
    return List.generate(
      pageCount,
      (i) => KsPage(
        index: i,
        imageUrl:
            buildImageUrl('/api/v1/chapter/$chapterId/page/$i').toString(),
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
