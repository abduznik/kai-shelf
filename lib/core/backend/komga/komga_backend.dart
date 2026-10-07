import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth_credentials.dart';
import '../models.dart';
import '../server_backend.dart';
import 'komga_mappers.dart';

/// Komga adapter — REST API, HTTP Basic Auth (email+password) or an
/// X-API-Key header, both accepted simultaneously per Komga's OpenAPI spec
/// (no session cookie exchange needed for API clients).
class KomgaBackend
    implements ServerBackend, CategoryCapableBackend, HistoryCapableBackend {
  KomgaBackend(ServerConnectionInfo connectionInfo, {http.Client? httpClient})
      : _connectionInfo = connectionInfo,
        _client = httpClient ?? http.Client();

  ServerConnectionInfo _connectionInfo;
  final http.Client _client;

  @override
  BackendType get type => BackendType.komga;

  @override
  ServerConnectionInfo get connectionInfo => _connectionInfo;

  Map<String, String> get _authHeaders => _connectionInfo.extraHeaders;

  Uri _uri(String path, [Map<String, String>? query]) {
    return _connectionInfo.baseUrl.replace(path: path, queryParameters: query);
  }

  String _basicAuthHeader(String email, String password) {
    return 'Basic ${base64Encode(utf8.encode('$email:$password'))}';
  }

  @override
  Future<AuthResult> login(AuthCredentials credentials) async {
    Map<String, String> headers;
    if (credentials is KomgaApiKeyCredentials) {
      headers = {'X-API-Key': credentials.apiKey};
    } else if (credentials is KomgaPasswordCredentials) {
      headers = {
        'Authorization':
            _basicAuthHeader(credentials.email, credentials.password)
      };
    } else {
      return const AuthResult.failure(
          'Komga backend received non-Komga credentials');
    }

    final response =
        await _client.get(_uri('/api/v2/users/me'), headers: headers);
    if (response.statusCode == 401) {
      return const AuthResult.failure('Incorrect email/password or API key.');
    }
    if (response.statusCode != 200) {
      return AuthResult.failure('Unexpected response (${response.statusCode})');
    }

    final updated = _connectionInfo.copyWith(
      apiKey: credentials is KomgaApiKeyCredentials ? credentials.apiKey : null,
      extraHeaders: headers,
    );
    _connectionInfo = updated;
    return AuthResult.success(updated);
  }

  @override
  Future<void> logout() async {
    _connectionInfo = _connectionInfo.copyWith(extraHeaders: const {});
  }

  @override
  Future<bool> validateSession() async {
    final response =
        await _client.get(_uri('/api/v2/users/me'), headers: _authHeaders);
    return response.statusCode == 200;
  }

  @override
  Future<List<KsLibrary>> getLibraries() async {
    final response =
        await _client.get(_uri('/api/v1/libraries'), headers: _authHeaders);
    _throwIfAuthError(response);
    final list = jsonDecode(response.body) as List;
    return list
        .map((json) =>
            KomgaMappers.libraryFromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<KsManga>> getMangaList(
      {String? libraryId, String? searchQuery, int page = 0}) async {
    final query = <String, String>{
      'page': page.toString(),
      'size': _pageSize.toString(),
    };
    if (libraryId != null) query['library_id'] = libraryId;
    if (searchQuery != null && searchQuery.isNotEmpty) {
      query['search'] = searchQuery;
    }

    final response =
        await _client.get(_uri('/api/v1/series', query), headers: _authHeaders);
    _throwIfAuthError(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['content'] as List;
    return content
        .map((json) => KomgaMappers.mangaFromJson(
              json as Map<String, dynamic>,
              buildImageUrl: buildImageUrl,
              coverHeaders: _authHeaders.isEmpty ? null : _authHeaders,
            ))
        .toList();
  }

  static const _pageSize = 200;

  @override
  Future<List<KsManga>> getAllManga(
      {String? libraryId, String? searchQuery}) async {
    final all = <KsManga>[];
    final seen = <String>{};
    for (var page = 0;; page++) {
      final batch = await getMangaList(
          libraryId: libraryId, searchQuery: searchQuery, page: page);
      // A repeated id means the server ignored the page parameter.
      final fresh = batch.where((m) => seen.add(m.id)).toList();
      all.addAll(fresh);
      if (batch.length < _pageSize || fresh.isEmpty) break;
    }
    return all;
  }

  @override
  Future<KsManga> getMangaDetail(String mangaId) async {
    final response = await _client.get(_uri('/api/v1/series/$mangaId'),
        headers: _authHeaders);
    _throwIfAuthError(response);
    return KomgaMappers.mangaFromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      buildImageUrl: buildImageUrl,
      coverHeaders: _authHeaders.isEmpty ? null : _authHeaders,
    );
  }

  @override
  Future<List<KsChapter>> getChapters(String mangaId) async {
    final response = await _client.get(
      _uri('/api/v1/series/$mangaId/books', {'unpaged': 'true'}),
      headers: _authHeaders,
    );
    _throwIfAuthError(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['content'] as List;
    return content
        .map((json) =>
            KomgaMappers.chapterFromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<KsPage>> getPages(String chapterId) async {
    final response = await _client.get(
      _uri('/api/v1/books/$chapterId/pages'),
      headers: _authHeaders,
    );
    _throwIfAuthError(response);
    final list = jsonDecode(response.body) as List;
    return list.map((json) {
      final pageNumber = json['number'] as int;
      return KsPage(
        index: pageNumber - 1,
        imageUrl: buildImageUrl('/api/v1/books/$chapterId/pages/$pageNumber')
            .toString(),
        extraHeaders: _authHeaders.isEmpty ? null : _authHeaders,
      );
    }).toList();
  }

  @override
  Future<void> updateReadProgress(String chapterId,
      {required bool read, double? lastPageRead}) async {
    final response = await _client.patch(
      _uri('/api/v1/books/$chapterId/read-progress'),
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({
        if (lastPageRead != null) 'page': lastPageRead.round(),
        'completed': read,
      }),
    );
    _throwIfAuthError(response);
  }

  /// Books that have any read progress (in progress or completed), ordered
  /// by when that progress was last written. `read_status` is repeated
  /// rather than comma-joined, which is what the endpoint's own docs use.
  @override
  Future<List<KsHistoryEntry>> getHistory(
      {int limit = 50, int offset = 0}) async {
    // Komga pages by page index, so [offset] must be a multiple of [limit].
    final uri = _connectionInfo.baseUrl.replace(
      path: '/api/v1/books',
      queryParameters: {
        'read_status': ['READ', 'IN_PROGRESS'],
        'sort': 'readProgress.lastModified,desc',
        'size': '$limit',
        'page': '${offset ~/ limit}',
      },
    );
    final response = await _client.get(uri, headers: _authHeaders);
    _throwIfAuthError(response);
    final content =
        (jsonDecode(response.body) as Map<String, dynamic>)['content'] as List;
    return content
        .map((json) => KomgaMappers.historyEntryFromJson(
              json as Map<String, dynamic>,
              buildImageUrl: buildImageUrl,
              coverHeaders: _authHeaders.isEmpty ? null : _authHeaders,
            ))
        .whereType<KsHistoryEntry>()
        .toList();
  }

  @override
  String get categoryNoun => 'collection';

  @override
  bool get canReorderCategories => false;

  /// Verified against Komga: POST /api/v1/collections answers 400 "seriesIds
  /// must not be empty", and so does PATCHing the list down to nothing.
  @override
  bool get canCreateEmptyCategory => false;

  Map<String, String> get _jsonHeaders =>
      {..._authHeaders, 'Content-Type': 'application/json'};

  /// Raises for any non-2xx answer, quoting Komga's validation message when
  /// it sent one.
  void _throwIfFailed(http.Response response) {
    _throwIfAuthError(response);
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    var message = 'Komga answered ${response.statusCode}';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['violations'] is List) {
        message = (body['violations'] as List)
            .map((v) => '${v['fieldName']} ${v['message']}')
            .join(', ');
      } else if (body is Map && body['message'] != null) {
        message = body['message'].toString();
      }
    } catch (_) {}
    throw BackendException(message);
  }

  @override
  Future<List<KsCategory>> getCategories() async {
    final response = await _client.get(
        _uri('/api/v1/collections', {'unpaged': 'true'}),
        headers: _authHeaders);
    _throwIfFailed(response);
    final content =
        (jsonDecode(response.body) as Map<String, dynamic>)['content'] as List;
    return content
        .map((j) => KomgaMappers.categoryFromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> _collection(String id) async {
    final response = await _client.get(_uri('/api/v1/collections/$id'),
        headers: _authHeaders);
    _throwIfFailed(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<KsCategory> createCategory(String name, {String? firstMangaId}) async {
    if (firstMangaId == null) {
      throw const BackendException(
          'Komga collections cannot be empty. Create one from a manga.');
    }
    final response = await _client.post(
      _uri('/api/v1/collections'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'name': name,
        'ordered': false,
        'seriesIds': [firstMangaId],
      }),
    );
    _throwIfFailed(response);
    return KomgaMappers.categoryFromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<void> renameCategory(String categoryId, String name) async {
    final response = await _client.patch(
      _uri('/api/v1/collections/$categoryId'),
      headers: _jsonHeaders,
      body: jsonEncode({'name': name}),
    );
    _throwIfFailed(response);
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    final response = await _client
        .delete(_uri('/api/v1/collections/$categoryId'), headers: _authHeaders);
    _throwIfFailed(response);
  }

  @override
  Future<void> moveCategory(String categoryId, int newIndex) =>
      throw UnsupportedError('Komga sorts collections itself');

  @override
  Future<Set<String>> getMangaCategoryIds(String mangaId) async {
    final response = await _client.get(
        _uri('/api/v1/series/$mangaId/collections'),
        headers: _authHeaders);
    _throwIfFailed(response);
    return (jsonDecode(response.body) as List)
        .map((j) => (j as Map)['id'] as String)
        .toSet();
  }

  /// Komga has no add/remove-one-series call: PATCH replaces the whole
  /// series list, so each change reads the list first. A collection left
  /// without series is deleted because Komga rejects an empty one.
  @override
  Future<void> setMangaCategories(
      String mangaId, Set<String> categoryIds) async {
    final current = await getMangaCategoryIds(mangaId);
    for (final id in categoryIds.difference(current)) {
      final ids = ((await _collection(id))['seriesIds'] as List).cast<String>();
      await _replaceSeries(id, [...ids, mangaId]);
    }
    for (final id in current.difference(categoryIds)) {
      final ids = ((await _collection(id))['seriesIds'] as List)
          .cast<String>()
          .where((s) => s != mangaId)
          .toList();
      if (ids.isEmpty) {
        await deleteCategory(id);
      } else {
        await _replaceSeries(id, ids);
      }
    }
  }

  Future<void> _replaceSeries(String collectionId, List<String> ids) async {
    final response = await _client.patch(
      _uri('/api/v1/collections/$collectionId'),
      headers: _jsonHeaders,
      body: jsonEncode({'seriesIds': ids}),
    );
    _throwIfFailed(response);
  }

  @override
  Future<List<KsManga>> getCategoryManga(String categoryId) async {
    final response = await _client.get(
      _uri('/api/v1/series', {'collection_id': categoryId, 'unpaged': 'true'}),
      headers: _authHeaders,
    );
    _throwIfFailed(response);
    final content =
        (jsonDecode(response.body) as Map<String, dynamic>)['content'] as List;
    return content
        .map((json) => KomgaMappers.mangaFromJson(
              json as Map<String, dynamic>,
              buildImageUrl: buildImageUrl,
              coverHeaders: _authHeaders.isEmpty ? null : _authHeaders,
            ))
        .toList();
  }

  @override
  Uri buildImageUrl(String pathOrId) {
    if (pathOrId.startsWith('http')) return Uri.parse(pathOrId);
    return _connectionInfo.baseUrl.replace(path: pathOrId);
  }

  void _throwIfAuthError(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const BackendAuthException();
    }
  }
}
