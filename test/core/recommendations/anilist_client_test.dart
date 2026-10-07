import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/recommendations/anilist_client.dart';

String _reply(List<Map<String, dynamic>> nodes) => jsonEncode({
      'data': {
        'Media': {
          'id': 1,
          'recommendations': {'nodes': nodes}
        }
      }
    });

Map<String, dynamic> _node(int id, String romaji,
        {int rating = 5, String? english, bool adult = false}) =>
    {
      'rating': rating,
      'mediaRecommendation': {
        'id': id,
        'isAdult': adult,
        'title': {'romaji': romaji, 'english': english},
        'coverImage': {'large': 'https://img/$id.jpg'},
        'genres': ['Action'],
        'averageScore': 80,
      }
    };

void main() {
  test('parses recommendations and prefers english for searching', () async {
    final client = AniListClient(
      httpClient: MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['variables']['search'], 'Berserk');
        return http.Response(
            _reply([
              _node(2, 'Vagabond', rating: 40),
              _node(3, 'Shingeki no Kyojin', english: 'Attack on Titan'),
            ]),
            200);
      }),
    );
    final recs = await client.recommendationsFor('Berserk');
    expect(recs.map((r) => r.id), [2, 3]);
    expect(recs[0].searchTitle, 'Vagabond');
    expect(recs[1].searchTitle, 'Attack on Titan');
    expect(recs[0].coverUrl, 'https://img/2.jpg');
    expect(recs[0].rating, 40);
    expect(recs[0].averageScore, 80);
  });

  test('skips disliked pairings and null recommendations', () async {
    final client = AniListClient(
      httpClient: MockClient((_) async => http.Response(
          _reply([
            _node(2, 'Liked'),
            _node(3, 'Disliked', rating: -3),
            {'rating': 1, 'mediaRecommendation': null},
          ]),
          200)),
    );
    final recs = await client.recommendationsFor('x');
    expect(recs.map((r) => r.id), [2]);
  });

  test('no match (404 with null Media) yields empty and is cached', () async {
    var calls = 0;
    final client = AniListClient(
      httpClient: MockClient((_) async {
        calls++;
        return http.Response(
            jsonEncode({
              'data': {'Media': null},
              'errors': [
                {'message': 'Not Found.', 'status': 404}
              ]
            }),
            404);
      }),
    );
    expect(await client.recommendationsFor('zzzz nothing'), isEmpty);
    expect(await client.recommendationsFor('ZZZZ nothing!'), isEmpty);
    expect(calls, 1);
  });

  test('errors degrade to empty and are retried next time', () async {
    var calls = 0;
    final client = AniListClient(
      httpClient: MockClient((_) async {
        calls++;
        if (calls == 1) return http.Response('boom', 500);
        return http.Response(_reply([_node(2, 'Vagabond')]), 200);
      }),
    );
    expect(await client.recommendationsFor('Berserk'), isEmpty);
    expect((await client.recommendationsFor('Berserk')).single.id, 2);
    expect(calls, 2);
  });

  test('network exceptions never escape', () async {
    final client = AniListClient(
      httpClient: MockClient((_) async => throw http.ClientException('down')),
    );
    expect(await client.recommendationsFor('Berserk'), isEmpty);
  });

  test('caches by normalised title, including concurrent callers', () async {
    var calls = 0;
    final client = AniListClient(
      httpClient: MockClient((_) async {
        calls++;
        return http.Response(_reply([_node(2, 'Vagabond')]), 200);
      }),
    );
    final results = await Future.wait([
      client.recommendationsFor('Berserk'),
      client.recommendationsFor('berserk!'),
    ]);
    expect(results.every((r) => r.length == 1), isTrue);
    await client.recommendationsFor(' BERSERK ');
    expect(calls, 1);

    client.clearCache();
    await client.recommendationsFor('Berserk');
    expect(calls, 2);
  });

  test('rate limit stops requests without throwing and recovers', () async {
    var calls = 0;
    var now = DateTime(2026, 1, 1);
    final client = AniListClient(
      maxRequestsPerMinute: 2,
      now: () => now,
      httpClient: MockClient((_) async {
        calls++;
        return http.Response(_reply([_node(2, 'Vagabond')]), 200);
      }),
    );
    await client.recommendationsFor('a');
    await client.recommendationsFor('b');
    expect(await client.recommendationsFor('c'), isEmpty);
    expect(calls, 2);

    now = now.add(const Duration(minutes: 2));
    expect(await client.recommendationsFor('c'), isNotEmpty);
    expect(calls, 3);
  });

  test('blank titles make no request', () async {
    var calls = 0;
    final client = AniListClient(
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    expect(await client.recommendationsFor('  !! '), isEmpty);
    expect(calls, 0);
  });
}
