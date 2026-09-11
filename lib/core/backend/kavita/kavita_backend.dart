import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth_credentials.dart';
import '../models.dart';
import '../server_backend.dart';
import 'kavita_mappers.dart';

/// Kavita adapter — REST API, an API key exchanged for a JWT access/refresh
/// pair via /api/Plugin/authenticate, then sent as a Bearer token on every
/// subsequent request. Series > Volumes > Chapters hierarchy is flattened:
/// each KsChapter maps to one Kavita ChapterDto.
class KavitaBackend implements ServerBackend {
  KavitaBackend(ServerConnectionInfo connectionInfo, {http.Client? httpClient})
      : _connectionInfo = connectionInfo,
        _client = httpClient ?? http.Client();

  ServerConnectionInfo _connectionInfo;
  final http.Client _client;

  /// Kavita's mark-progress endpoint requires the owning libraryId
  /// alongside series/chapter ids, and getPages only receives a chapterId
  /// with no page count — cache both as chapters are fetched via
  /// getChapters so later calls don't need an extra round trip (or, worse,
  /// a guessed endpoint that was never confirmed against the real API).
  final Map<String, ({String seriesId, String libraryId, int pageCount})>
      _chapterContext = {};

  @override
  BackendType get type => BackendType.kavita;

  @override
  ServerConnectionInfo get connectionInfo => _connectionInfo;

  Map<String, String> get _authHeaders => _connectionInfo.extraHeaders;

  Uri _uri(String path, [Map<String, String>? query]) {
    return _connectionInfo.baseUrl.replace(path: path, queryParameters: query);
  }

  @override
  Future<AuthResult> login(AuthCredentials credentials) async {
    if (credentials is! KavitaCredentials) {
      return const AuthResult.failure(
          'Kavita backend received non-Kavita credentials');
    }

    final response = await _client.post(
      _uri('/api/Plugin/authenticate',
          {'apiKey': credentials.apiKey, 'pluginName': 'kai-shelf'}),
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      return const AuthResult.failure('Invalid API key.');
    }
    if (response.statusCode != 200) {
      return AuthResult.failure('Unexpected response (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String?;
    final refreshToken = body['refreshToken'] as String?;
    if (token == null) {
      return const AuthResult.failure('Server did not return a token');
    }

    final updated = _connectionInfo.copyWith(
      apiKey: credentials.apiKey,
      sessionToken: token,
      refreshToken: refreshToken,
      extraHeaders: {'Authorization': 'Bearer $token'},
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
        await _client.get(_uri('/api/Health'), headers: _authHeaders);
    return response.statusCode == 200;
  }

  @override
  Future<List<KsLibrary>> getLibraries() async {
    final response = await _client.get(_uri('/api/Library/libraries'),
        headers: _authHeaders);
    _throwIfAuthError(response);
    final list = jsonDecode(response.body) as List;
    return list
        .map((json) =>
            KavitaMappers.libraryFromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<KsManga>> getMangaList(
      {String? libraryId, String? searchQuery, int page = 0}) async {
    final response = await _client.post(
      _uri('/api/Series/v2', {'PageNumber': (page + 1).toString()}),
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({
        if (libraryId != null) 'libraryId': int.parse(libraryId),
        if (searchQuery != null && searchQuery.isNotEmpty)
          'searchTerm': searchQuery,
      }),
    );
    _throwIfAuthError(response);
    final list = jsonDecode(response.body) as List;
    return list
        .map((json) => KavitaMappers.mangaFromJson(
              json as Map<String, dynamic>,
              buildImageUrl: buildImageUrl,
              coverHeaders: _authHeaders.isEmpty ? null : _authHeaders,
            ))
        .toList();
  }

  @override
  Future<KsManga> getMangaDetail(String mangaId) async {
    final seriesResponse = await _client.get(
      _uri('/api/Series/$mangaId'),
      headers: _authHeaders,
    );
    _throwIfAuthError(seriesResponse);
    final seriesJson = jsonDecode(seriesResponse.body) as Map<String, dynamic>;

    final metadataResponse = await _client.get(
      _uri('/api/Series/metadata', {'seriesId': mangaId}),
      headers: _authHeaders,
    );
    final metadataJson = metadataResponse.statusCode == 200
        ? jsonDecode(metadataResponse.body) as Map<String, dynamic>
        : null;

    return KavitaMappers.mangaFromJson(
      seriesJson,
      metadata: metadataJson,
      buildImageUrl: buildImageUrl,
      coverHeaders: _authHeaders.isEmpty ? null : _authHeaders,
    );
  }

  @override
  Future<List<KsChapter>> getChapters(String mangaId) async {
    final response = await _client.get(
      _uri('/api/Series/volumes', {'seriesId': mangaId}),
      headers: _authHeaders,
    );
    _throwIfAuthError(response);
    final volumes = jsonDecode(response.body) as List;

    final libraryId =
        (await getMangaDetail(mangaId)).backendExtra['libraryId'].toString();

    final chapters = <KsChapter>[];
    for (final volume in volumes) {
      final chapterList =
          (volume as Map<String, dynamic>)['chapters'] as List? ?? [];
      for (final chapterJson in chapterList) {
        final chapter = KavitaMappers.chapterFromJson(
          chapterJson as Map<String, dynamic>,
          mangaId: mangaId,
        );
        _chapterContext[chapter.id] = (
          seriesId: mangaId,
          libraryId: libraryId,
          pageCount: chapter.pageCount ?? 0,
        );
        chapters.add(chapter);
      }
    }
    return chapters;
  }

  @override
  Future<List<KsPage>> getPages(String chapterId) async {
    // Kavita's ChapterDto (fetched via getChapters, which populates
    // _chapterContext) already carries the page count — there's no
    // separate "list pages" endpoint to call here.
    final context = _chapterContext[chapterId];
    if (context == null) {
      throw StateError(
          'getPages called before getChapters populated context for $chapterId');
    }

    return List.generate(
      context.pageCount,
      (i) => KsPage(
        index: i,
        imageUrl:
            buildImageUrl('/api/Reader/image?chapterId=$chapterId&page=$i')
                .toString(),
        extraHeaders: _authHeaders.isEmpty ? null : _authHeaders,
      ),
    );
  }

  @override
  Future<void> updateReadProgress(String chapterId,
      {required bool read, double? lastPageRead}) async {
    final context = _chapterContext[chapterId];
    if (context == null) {
      throw StateError(
          'updateReadProgress called before getChapters populated context for $chapterId');
    }

    if (read) {
      final response = await _client.post(
        _uri('/api/Reader/mark-chapter-read'),
        headers: {..._authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'seriesId': int.parse(context.seriesId),
          'chapterId': int.parse(chapterId)
        }),
      );
      _throwIfAuthError(response);
      return;
    }

    final response = await _client.post(
      _uri('/api/Reader/progress'),
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'seriesId': int.parse(context.seriesId),
        'libraryId': int.parse(context.libraryId),
        'volumeId': 0,
        'chapterId': int.parse(chapterId),
        'pageNum': (lastPageRead ?? 0).round(),
      }),
    );
    _throwIfAuthError(response);
  }

  @override
  Uri buildImageUrl(String pathOrId) {
    if (pathOrId.startsWith('http')) return Uri.parse(pathOrId);
    final uri = Uri.parse(pathOrId);
    return _connectionInfo.baseUrl
        .replace(path: uri.path, queryParameters: uri.queryParameters);
  }

  void _throwIfAuthError(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const BackendAuthException();
    }
  }
}
