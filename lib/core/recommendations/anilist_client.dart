import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'title_matching.dart';

/// One title AniList suggests for readers of another.
class AniListRecommendation {
  const AniListRecommendation({
    required this.id,
    required this.romaji,
    this.english,
    this.coverUrl,
    this.genres = const [],
    this.averageScore,
    this.rating = 0,
    this.isAdult = false,
  });

  final int id;
  final String romaji;
  final String? english;
  final String? coverUrl;
  final List<String> genres;

  /// AniList's 0-100 community score for the recommended title itself.
  final int? averageScore;

  /// Net user votes on this specific recommendation pairing.
  final int rating;
  final bool isAdult;

  /// The title to search sources with. Sources index English names more
  /// consistently than romaji, so prefer it when AniList has one.
  String get searchTitle =>
      (english != null && english!.trim().isNotEmpty) ? english! : romaji;

  /// Every name we can compare against a library title.
  List<String> get allTitles => [
        romaji,
        if (english != null && english!.trim().isNotEmpty) english!,
      ];
}

/// Thin client for AniList's public GraphQL API. Recommendations are a
/// nice-to-have, so every failure mode (offline, rate limited, no match,
/// malformed reply) degrades to an empty list instead of throwing.
class AniListClient {
  AniListClient({
    required http.Client httpClient,
    Uri? endpoint,
    this.maxRequestsPerMinute = 80,
    DateTime Function()? now,
  })  : _http = httpClient,
        _endpoint = endpoint ?? Uri.parse('https://graphql.anilist.co'),
        _now = now ?? DateTime.now;

  final http.Client _http;
  final Uri _endpoint;

  /// AniList allows roughly 90/min; stay a little under so a burst from
  /// several screens cannot get the client throttled.
  final int maxRequestsPerMinute;
  final DateTime Function() _now;

  final Map<String, Future<List<AniListRecommendation>>> _cache = {};
  final List<DateTime> _sent = [];

  static const _query = r'''
query ($search: String, $perPage: Int) {
  Media(search: $search, type: MANGA) {
    id
    recommendations(perPage: $perPage, sort: RATING_DESC) {
      nodes {
        rating
        mediaRecommendation {
          id
          isAdult
          title { romaji english }
          coverImage { large }
          genres
          averageScore
        }
      }
    }
  }
}
''';

  /// Forgets cached answers, for an explicit user refresh.
  void clearCache() => _cache.clear();

  /// Recommendations for the best AniList match of [title], best-rated
  /// first. Results (including "nothing found") are cached per normalised
  /// title; failures are not, so a later call can retry.
  Future<List<AniListRecommendation>> recommendationsFor(String title,
      {int perPage = 10}) {
    final normalized = normalizeTitle(title);
    if (normalized.isEmpty) return Future.value(const []);
    final key = '$normalized|$perPage';
    final cached = _cache[key];
    if (cached != null) return cached;
    final future = _fetch(title, perPage).then((r) {
      if (r == null) _cache.remove(key);
      return r ?? const <AniListRecommendation>[];
    });
    _cache[key] = future;
    return future;
  }

  bool _acquireSlot() {
    final cutoff = _now().subtract(const Duration(minutes: 1));
    _sent.removeWhere((t) => t.isBefore(cutoff));
    if (_sent.length >= maxRequestsPerMinute) return false;
    _sent.add(_now());
    return true;
  }

  /// Returns null on a failure worth retrying, an empty list for a
  /// definitive "no match".
  Future<List<AniListRecommendation>?> _fetch(String title, int perPage) async {
    if (!_acquireSlot()) return null;
    try {
      final response = await _http
          .post(
            _endpoint,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'query': _query,
              'variables': {'search': title.trim(), 'perPage': perPage},
            }),
          )
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final media = (decoded['data'] as Map<String, dynamic>?)?['Media'];
      if (media is Map<String, dynamic>) return _parse(media);
      // AniList answers an unmatched search with HTTP 404 and a null Media.
      if (response.statusCode == 404) return const [];
      return null;
    } catch (_) {
      return null;
    }
  }

  List<AniListRecommendation> _parse(Map<String, dynamic> media) {
    final nodes = ((media['recommendations'] as Map<String, dynamic>?)?['nodes']
            as List?) ??
        const [];
    final out = <AniListRecommendation>[];
    for (final node in nodes) {
      if (node is! Map<String, dynamic>) continue;
      final m = node['mediaRecommendation'];
      if (m is! Map<String, dynamic>) continue;
      final id = m['id'];
      final titles = m['title'] as Map<String, dynamic>?;
      final romaji =
          titles?['romaji'] as String? ?? titles?['english'] as String?;
      if (id is! int || romaji == null) continue;
      final rating = (node['rating'] as num?)?.toInt() ?? 0;
      // Negative votes mean readers actively disliked the pairing.
      if (rating < 0) continue;
      out.add(AniListRecommendation(
        id: id,
        romaji: romaji,
        english: titles?['english'] as String?,
        coverUrl:
            (m['coverImage'] as Map<String, dynamic>?)?['large'] as String?,
        genres: [
          for (final g in (m['genres'] as List?) ?? const [])
            if (g is String) g
        ],
        averageScore: (m['averageScore'] as num?)?.toInt(),
        rating: rating,
        isAdult: m['isAdult'] == true,
      ));
    }
    return out;
  }
}
