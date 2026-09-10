import 'dart:convert';

import 'package:graphql/client.dart';

import '../auth_credentials.dart';
import '../models.dart';
import '../server_backend.dart';
import 'suwayomi_mappers.dart';
import 'suwayomi_queries.dart';

/// Suwayomi (Tachidesk) adapter — talks to a single GraphQL endpoint.
/// Auth, when the server has a password set, rides as a Basic auth header
/// on every request rather than a separate session exchange.
class SuwayomiBackend implements ServerBackend {
  SuwayomiBackend(ServerConnectionInfo connectionInfo)
      : _connectionInfo = connectionInfo {
    _client = _buildClient(connectionInfo);
  }

  ServerConnectionInfo _connectionInfo;
  late GraphQLClient _client;

  @override
  BackendType get type => BackendType.suwayomi;

  @override
  ServerConnectionInfo get connectionInfo => _connectionInfo;

  GraphQLClient _buildClient(ServerConnectionInfo info) {
    final httpLink = HttpLink(
      info.baseUrl.replace(path: '/api/graphql').toString(),
      defaultHeaders: info.extraHeaders,
    );
    return GraphQLClient(link: httpLink, cache: GraphQLCache());
  }

  @override
  Future<AuthResult> login(AuthCredentials credentials) async {
    if (credentials is! SuwayomiCredentials) {
      return const AuthResult.failure(
          'Suwayomi backend received non-Suwayomi credentials');
    }

    var headers = <String, String>{};
    if (credentials.password != null && credentials.password!.isNotEmpty) {
      final basicAuth =
          'Basic ${_encodeBasicAuth('admin', credentials.password!)}';
      headers = {'Authorization': basicAuth};
    }

    final updated = _connectionInfo.copyWith(extraHeaders: headers);
    _client = _buildClient(updated);

    final result = await _client.query(
      QueryOptions(
          document: gql(SuwayomiQueries.aboutQuery),
          fetchPolicy: FetchPolicy.noCache),
    );

    if (result.hasException) {
      return AuthResult.failure(result.exception.toString());
    }

    _connectionInfo = updated;
    return AuthResult.success(updated);
  }

  String _encodeBasicAuth(String user, String password) {
    return base64Encode(utf8.encode('$user:$password'));
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
