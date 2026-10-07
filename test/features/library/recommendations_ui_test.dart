import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/server_backend.dart';
import 'package:kai_shelf/core/providers/backend_providers.dart';
import 'package:kai_shelf/core/providers/recommendation_providers.dart';
import 'package:kai_shelf/core/recommendations/anilist_client.dart';
import 'package:kai_shelf/features/library/presentation/feed_screen.dart';
import 'package:kai_shelf/features/library/presentation/global_search_screen.dart';
import 'package:kai_shelf/features/library/presentation/recommended_screen.dart';
import 'package:kai_shelf/features/library/presentation/widgets/more_like_this_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../extensions/fake_backend.dart';

/// Answers browse calls with titles that reveal which source and mode asked.
class _BrowseBackend extends FakeCatalogBackend {
  _BrowseBackend({this.libraryManga = const []});

  final List<KsManga> libraryManga;
  final List<String> searches = [];
  final List<String> latestFor = [];

  @override
  Future<List<KsManga>> getAllManga(
          {String? libraryId, String? searchQuery}) async =>
      libraryManga;

  @override
  Future<KsSourcePage> browseSource(
    String sourceId, {
    SourceBrowseMode mode = SourceBrowseMode.popular,
    String query = '',
    int page = 1,
    List<KsFilterChange> filters = const [],
  }) async {
    if (mode == SourceBrowseMode.search) searches.add('$sourceId:$query');
    if (mode == SourceBrowseMode.latest) latestFor.add(sourceId);
    final label = mode == SourceBrowseMode.search ? query : 'Latest';
    return KsSourcePage(
      items: [KsSourceManga(id: 'm$sourceId', title: '$label from $sourceId')],
      hasNextPage: false,
    );
  }
}

/// A backend without source support, like Komga/Kavita.
class _PlainBackend implements ServerBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

AniListClient _client(Map<String, dynamic> Function(String search) reply,
    {List<String>? searched}) {
  return AniListClient(
    httpClient: MockClient((req) async {
      final search = jsonDecode(req.body)['variables']['search'] as String;
      searched?.add(search);
      return http.Response(jsonEncode(reply(search)), 200);
    }),
  );
}

Map<String, dynamic> _recs(List<(int, String)> titles) => {
      'data': {
        'Media': {
          'id': 1,
          'recommendations': {
            'nodes': [
              for (final t in titles)
                {
                  'rating': 3,
                  'mediaRecommendation': {
                    'id': t.$1,
                    'isAdult': false,
                    'title': {'romaji': t.$2, 'english': null},
                    'coverImage': {'large': null},
                    'genres': <String>[],
                    'averageScore': 80,
                  }
                }
            ]
          }
        }
      }
    };

/// Spinners animate forever, so pumpAndSettle would never return.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(
  Widget home, {
  required ServerBackend backend,
  required AniListClient client,
}) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => Scaffold(body: home)),
    GoRoute(
      path: '/discover/all',
      builder: (_, state) =>
          GlobalSearchScreen(initialQuery: state.uri.queryParameters['q']),
    ),
  ]);
  return ProviderScope(
    overrides: [
      activeBackendProvider.overrideWithValue(backend),
      aniListClientProvider.overrideWithValue(client),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('MoreLikeThisRow', () {
    testWidgets('shows recommendations and tap searches all sources',
        (tester) async {
      final backend = _BrowseBackend();
      final client = _client((_) => _recs([(2, 'Vagabond'), (3, 'Monster')]));
      await tester.pumpWidget(_app(const MoreLikeThisRow(title: 'Berserk'),
          backend: backend, client: client));
      await _settle(tester);

      expect(find.text('More like this'), findsOneWidget);
      expect(find.text('Vagabond'), findsOneWidget);

      await tester.tap(find.text('Vagabond'));
      await _settle(tester);

      // Pre-filled, searched on both sources, results listed per source.
      expect(find.widgetWithText(TextField, 'Vagabond'), findsOneWidget);
      expect(backend.searches, containsAll(['1:Vagabond', '2:Vagabond']));
      expect(find.text('Vagabond from 1'), findsOneWidget);
    });

    testWidgets('hidden when AniList has nothing', (tester) async {
      final client = _client((_) => _recs([]));
      await tester.pumpWidget(_app(const MoreLikeThisRow(title: 'Obscure'),
          backend: _BrowseBackend(), client: client));
      await _settle(tester);
      expect(find.text('More like this'), findsNothing);
    });

    testWidgets('hidden and silent when the request fails', (tester) async {
      final client = AniListClient(
          httpClient: MockClient((_) async => http.Response('nope', 500)));
      await tester.pumpWidget(_app(const MoreLikeThisRow(title: 'Berserk'),
          backend: _BrowseBackend(), client: client));
      await _settle(tester);
      expect(find.text('More like this'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('never queries AniList for non-source backends',
        (tester) async {
      final searched = <String>[];
      final client =
          _client((_) => _recs([(2, 'Vagabond')]), searched: searched);
      await tester.pumpWidget(_app(const MoreLikeThisRow(title: 'Berserk'),
          backend: _PlainBackend(), client: client));
      await _settle(tester);
      expect(find.text('More like this'), findsNothing);
      expect(searched, isEmpty);
    });
  });

  group('RecommendedScreen', () {
    testWidgets('aggregates, drops owned titles, tap searches sources',
        (tester) async {
      final backend = _BrowseBackend(libraryManga: [
        KsManga(id: '1', title: 'Berserk', lastUpdated: DateTime(2026)),
        KsManga(id: '2', title: 'Monster', lastUpdated: DateTime(2025)),
      ]);
      final client = _client((search) => _recs([
            (10, 'Vagabond'),
            (11, 'Monster'), // already owned
          ]));
      await tester.pumpWidget(
          _app(const RecommendedScreen(), backend: backend, client: client));
      await _settle(tester);

      expect(find.text('Vagabond'), findsOneWidget);
      expect(find.text('Fits 2 of your titles'), findsOneWidget);
      expect(find.text('Monster'), findsNothing);

      await tester.tap(find.text('Vagabond'));
      await _settle(tester);
      expect(backend.searches, contains('1:Vagabond'));
    });

    testWidgets('refresh re-queries AniList', (tester) async {
      final searched = <String>[];
      final backend = _BrowseBackend(libraryManga: [
        KsManga(id: '1', title: 'Berserk'),
      ]);
      final client =
          _client((_) => _recs([(10, 'Vagabond')]), searched: searched);
      await tester.pumpWidget(
          _app(const RecommendedScreen(), backend: backend, client: client));
      await _settle(tester);
      expect(searched, ['Berserk']);

      await tester.tap(find.byTooltip('Refresh'));
      await _settle(tester);
      expect(searched, ['Berserk', 'Berserk']);
    });
  });

  group('FeedScreen', () {
    testWidgets('shows one row per chosen source and remembers the choice',
        (tester) async {
      final backend = _BrowseBackend();
      await tester.pumpWidget(_app(const FeedScreen(),
          backend: backend, client: _client((_) => _recs([]))));
      await _settle(tester);

      // No saved choice: defaults to the available sources' latest listing.
      expect(backend.latestFor.toSet(), {'1', '2'});
      expect(find.text('Latest from 1'), findsOneWidget);
      expect(find.text('Latest from 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Choose sources'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Beta'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await _settle(tester);

      expect(find.text('Latest from 1'), findsOneWidget);
      expect(find.text('Latest from 2'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('feed.sourceIds'), ['1']);
    });

    testWidgets('uses the saved selection', (tester) async {
      SharedPreferences.setMockInitialValues({
        'feed.sourceIds': ['2']
      });
      final backend = _BrowseBackend();
      await tester.pumpWidget(_app(const FeedScreen(),
          backend: backend, client: _client((_) => _recs([]))));
      await _settle(tester);
      expect(backend.latestFor, ['2']);
    });
  });
}
