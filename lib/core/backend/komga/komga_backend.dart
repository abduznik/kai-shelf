import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth_credentials.dart';
import '../models.dart';
import '../server_backend.dart';
import 'komga_mappers.dart';

/// Komga adapter — REST API, HTTP Basic Auth (email+password) or an
/// X-API-Key header, both accepted simultaneously per Komga's OpenAPI spec
/// (no session cookie exchange needed for API clients).
class KomgaBackend implements ServerBackend {
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
    final query = <String, String>{'page': page.toString()};
    if (libraryId != null) query['library_id'] = libraryId;
    if (searchQuery != null && searchQuery.isNotEmpty)
      query['search'] = searchQuery;

    final response =
        await _client.get(_uri('/api/v1/series', query), headers: _authHeaders);
    _throwIfAuthError(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['content'] as List;
    return content
        .map((json) => KomgaMappers.mangaFromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<KsManga> getMangaDetail(String mangaId) async {
    final response = await _client.get(_uri('/api/v1/series/$mangaId'),
        headers: _authHeaders);
    _throwIfAuthError(response);
    return KomgaMappers.mangaFromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
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
