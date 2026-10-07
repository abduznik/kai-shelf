import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/recommendations/anilist_client.dart';
import 'package:kai_shelf/core/recommendations/recommendation_ranking.dart';
import 'package:kai_shelf/core/recommendations/title_matching.dart';

AniListRecommendation _rec(int id, String romaji,
        {int rating = 0, int? score, String? english, bool adult = false}) =>
    AniListRecommendation(
      id: id,
      romaji: romaji,
      english: english,
      rating: rating,
      averageScore: score,
      isAdult: adult,
    );

void main() {
  group('titlesMatch', () {
    test('ignores case and punctuation', () {
      expect(titlesMatch('Berserk', 'BERSERK!'), isTrue);
      expect(titlesMatch('Dr. STONE', 'Dr Stone'), isTrue);
    });

    test('does not treat a longer distinct title as a match', () {
      expect(titlesMatch('One Piece', 'One Piece Party'), isFalse);
      expect(titlesMatch('Berserk', 'Vagabond'), isFalse);
    });

    test('empty never matches', () {
      expect(titlesMatch('', ''), isFalse);
      expect(titlesMatch('!!', 'berserk'), isFalse);
    });
  });

  group('aggregateRecommendations', () {
    test('ranks by library votes, then rating, then score', () {
      final result = aggregateRecommendations([
        [
          _rec(1, 'A', rating: 10, score: 70),
          _rec(2, 'B', rating: 50, score: 60),
          _rec(3, 'C', rating: 10, score: 90),
        ],
        [_rec(1, 'A', rating: 5, score: 70), _rec(3, 'C', rating: 10)],
        [_rec(4, 'D', rating: 10, score: 95)],
      ], const []);
      // A and C each recommended twice; C has rating 20 vs A's 15.
      expect(result.map((r) => r.recommendation.id), [3, 1, 2, 4]);
      expect(result.first.votes, 2);
      expect(result.first.rating, 20);
    });

    test('drops titles already in the library, matching either name', () {
      final result = aggregateRecommendations([
        [
          _rec(1, 'Shingeki no Kyojin', english: 'Attack on Titan'),
          _rec(2, 'Vagabond'),
          _rec(3, 'Dr. STONE'),
        ]
      ], [
        'attack on titan',
        'Dr Stone'
      ]);
      expect(result.map((r) => r.recommendation.id), [2]);
    });

    test('counts a title once per source list and hides adult entries', () {
      final result = aggregateRecommendations([
        [_rec(1, 'A'), _rec(1, 'A'), _rec(2, 'X', adult: true)],
      ], const []);
      expect(result.single.votes, 1);
      expect(
          aggregateRecommendations([
            [_rec(2, 'X', adult: true)]
          ], const [], allowAdult: true),
          hasLength(1));
    });

    test('empty input gives empty output', () {
      expect(aggregateRecommendations(const [], const []), isEmpty);
    });
  });

  group('pickSample', () {
    KsManga m(String id, DateTime? updated) =>
        KsManga(id: id, title: id, lastUpdated: updated);

    test('prefers recently updated titles and caps the count', () {
      final sample = pickSample([
        m('old', DateTime(2020)),
        m('none', null),
        m('new', DateTime(2026)),
        m('mid', DateTime(2024)),
      ], count: 3);
      expect(sample.map((e) => e.id), ['new', 'mid', 'old']);
    });
  });
}
