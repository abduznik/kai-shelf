@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kai_shelf/core/recommendations/anilist_client.dart';

/// Hits the real AniList API. Skipped unless KAI_NETWORK_TESTS=1 so CI stays
/// hermetic and does not depend on a third party being reachable.
void main() {
  final skip = Platform.environment['KAI_NETWORK_TESTS'] == '1'
      ? null
      : 'KAI_NETWORK_TESTS not set';

  test('Berserk has recommendations; gibberish has none', () async {
    final http_ = http.Client();
    addTearDown(http_.close);
    final client = AniListClient(httpClient: http_);

    final recs = await client.recommendationsFor('Berserk');
    expect(recs, isNotEmpty);
    expect(recs.first.coverUrl, startsWith('http'));
    expect(recs.first.searchTitle, isNotEmpty);

    expect(await client.recommendationsFor('qzxwvjkpl no such manga'), isEmpty);
  }, skip: skip);
}
