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
      _uri('/api/Series/v2', {
        'PageNumber': (page + 1).toString(),
        'PageSize': _pageSize.toString(),
      }),
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
          volume: volume,
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

  /// Series/library/page-count for a chapter. Normally cached by
  /// [getChapters], but a reader opened directly (deep link, page reload)
  /// never listed its series first, so fall back to resolving it from the
  /// chapter id: chapter -> volume -> series -> library.
  Future<({String seriesId, String libraryId, int pageCount})> _contextFor(
      String chapterId) async {
    final cached = _chapterContext[chapterId];
    if (cached != null) return cached;

    final chapterResponse = await _client.get(
        _uri('/api/Chapter', {'chapterId': chapterId}),
        headers: _authHeaders);
    _throwIfAuthError(chapterResponse);
    final chapterJson =
        jsonDecode(chapterResponse.body) as Map<String, dynamic>;

    final volumeResponse = await _client.get(
        _uri('/api/Series/volume', {'volumeId': '${chapterJson['volumeId']}'}),
        headers: _authHeaders);
    _throwIfAuthError(volumeResponse);
    final seriesId =
        (jsonDecode(volumeResponse.body) as Map<String, dynamic>)['seriesId']
            .toString();

    final libraryId =
        (await getMangaDetail(seriesId)).backendExtra['libraryId'].toString();
    final context = (
      seriesId: seriesId,
      libraryId: libraryId,
      pageCount: (chapterJson['pages'] as num?)?.toInt() ?? 0,
    );
    _chapterContext[chapterId] = context;
    return context;
  }

  @override
  Future<List<KsPage>> getPages(String chapterId) async {
    // Kavita's ChapterDto (fetched via getChapters, which populates
    // _chapterContext) already carries the page count — there's no
    // separate "list pages" endpoint to call here.
    final context = await _contextFor(chapterId);

    return List.generate(
      context.pageCount,
      (i) => KsPage(
        index: i,
        imageUrl:
            // Confirmed against a live Kavita: the reader image endpoint
            // 400s ("apiKey field is required") unless the key is also a
            // query parameter, even when a Bearer header is sent.
            _withApiKey(buildImageUrl(
                    '/api/Reader/image?chapterId=$chapterId&page=$i'))
                .toString(),
        extraHeaders: _authHeaders.isEmpty ? null : _authHeaders,
      ),
    );
  }

  @override
  Future<void> updateReadProgress(String chapterId,
      {required bool read, double? lastPageRead}) async {
    final context = await _contextFor(chapterId);

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

  Uri _withApiKey(Uri uri) {
    final key = _connectionInfo.apiKey;
    if (key == null || key.isEmpty) return uri;
    return uri
        .replace(queryParameters: {...uri.queryParameters, 'apiKey': key});
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
