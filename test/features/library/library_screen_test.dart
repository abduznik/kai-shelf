// Widget coverage for the library screen (issue #18): grid rendering, the
// search box driving the shared filter provider, the sort & filter sheet's
// status/sort round-trip with its badge count, per-library chips, the empty
// state, capability-gated app bar actions and navigation to the title screen.
// Semantics live in library_a11y_test.dart, the provider hand-off from the
// title screen's genre chips in genre_chip_filter_test.dart, and the pure
// filter/sort logic in library_filter_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/server_backend.dart';
import 'package:kai_shelf/core/providers/backend_providers.dart';
import 'package:kai_shelf/features/library/domain/library_filter.dart';
import 'package:kai_shelf/features/library/presentation/library_filter_provider.dart';
import 'package:kai_shelf/features/library/presentation/library_screen.dart';
import 'package:kai_shelf/features/library/presentation/manga_detail_screen.dart';
import 'package:kai_shelf/features/library/presentation/widgets/library_filter_sheet.dart';
import 'package:kai_shelf/features/library/presentation/widgets/manga_grid_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _allManga = [
  KsManga(
      id: 'm1',
      title: 'Berserk',
      genres: ['Action'],
      status: MangaStatus.ongoing),
  KsManga(
      id: 'm2',
      title: 'Nana',
      genres: ['Drama'],
      status: MangaStatus.completed),
  KsManga(
      id: 'm3',
      title: 'Monster',
      genres: ['Mystery'],
      status: MangaStatus.ongoing),
];

/// In-memory backend: a library list, per-library manga lists and just
/// enough of the detail API for a tile tap to open the title screen.
class _PlainBackend implements ServerBackend {
  _PlainBackend({
    List<KsLibrary>? libraries,
    List<KsManga>? manga,
    this.mangaByLibrary = const {},
  })  : libraries = libraries ??
            const [KsLibrary(id: 'all', name: 'All', mangaCount: 3)],
        manga = manga ?? _allManga;

  final List<KsLibrary> libraries;
  final List<KsManga> manga;

  /// Titles per library id, for the chip row's library switch.
  final Map<String, List<KsManga>> mangaByLibrary;

  /// The libraryId every getAllManga call asked for, in order.
  final List<String?> libraryRequests = [];

  @override
  Future<List<KsLibrary>> getLibraries() async => libraries;

  @override
  Future<List<KsManga>> getAllManga(
      {String? libraryId, String? searchQuery}) async {
    libraryRequests.add(libraryId);
    if (libraryId == null) return manga;
    return mangaByLibrary[libraryId] ?? const [];
  }

  @override
  Future<KsManga> getMangaDetail(String mangaId) async => [
        ...manga,
        for (final list in mangaByLibrary.values) ...list,
      ].firstWhere((m) => m.id == mangaId);

  @override
  Future<List<KsChapter>> getChapters(String mangaId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A backend that supports sources, extensions and categories, so the
/// capability-gated app bar actions appear.
class _CapableBackend extends _PlainBackend
    implements
        SourceCapableBackend,
        ExtensionCapableBackend,
        CategoryCapableBackend {
  @override
  String get categoryNoun => 'category';

  @override
  bool get canReorderCategories => true;

  @override
  bool get canCreateEmptyCategory => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Widget _app({ServerBackend? backend, List<String>? visited}) {
  final router = GoRouter(
    initialLocation: '/library',
    routes: [
      GoRoute(
          path: '/', builder: (_, __) => const Scaffold(body: Text('home'))),
      GoRoute(path: '/library', builder: (_, __) => const LibraryScreen()),
      GoRoute(
        path: '/manga/:mangaId',
        builder: (_, state) {
          visited?.add(state.uri.path);
          return MangaDetailScreen(mangaId: state.pathParameters['mangaId']!);
        },
      ),
      GoRoute(
        path: '/recommended',
        builder: (_, __) {
          visited?.add('/recommended');
          return const Scaffold(body: Text('recommended'));
        },
      ),
      GoRoute(
        path: '/discover',
        builder: (_, __) {
          visited?.add('/discover');
          return const Scaffold(body: Text('discover'));
        },
      ),
      GoRoute(
        path: '/extensions',
        builder: (_, __) {
          visited?.add('/extensions');
          return const Scaffold(body: Text('extensions'));
        },
      ),
      GoRoute(
        path: '/categories',
        builder: (_, __) {
          visited?.add('/categories');
          return const Scaffold(body: Text('categories'));
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      if (backend != null) activeBackendProvider.overrideWithValue(backend),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// A phone-tall window, so every grid tile and sheet row is on screen.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Grid titles in the order the grid builds them (i.e. the sorted order).
List<String> _tileTitles(WidgetTester tester) => tester
    .widgetList<MangaGridTile>(find.byType(MangaGridTile))
    .map((tile) => tile.manga.title)
    .toList();

Finder _badgeLabel(String count) => find.descendant(
    of: find.byTooltip('Sort & filter'), matching: find.text(count));

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('LibraryScreen prompts to connect when no server is active',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Not connected to a server yet.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget,
        reason: 'Connect must route to the connect screen');
  });

  testWidgets(
      'renders the grid with the search box and no chip row for a single '
      'library', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(backend: _PlainBackend()));
    await tester.pumpAndSettle();

    final search = find.byType(TextField);
    expect(search, findsOneWidget,
        reason: 'the library always offers the search box');
    expect(tester.widget<TextField>(search).decoration?.hintText,
        'Search library');

    expect(find.byType(MangaGridTile), findsNWidgets(3));
    expect(_tileTitles(tester), ['Berserk', 'Monster', 'Nana'],
        reason: 'the default sort is title ascending');
    expect(find.byType(ChoiceChip), findsNothing,
        reason: 'one library means no library switcher row');
    expect(find.byTooltip('Sort & filter'), findsOneWidget);
  });

  testWidgets('the search box narrows the grid through the shared filter',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(backend: _PlainBackend()));
    await tester.pumpAndSettle();
    final container = _containerOf(tester);

    await tester.enterText(find.byType(TextField), 'nan');
    await tester.pumpAndSettle();
    expect(container.read(libraryFilterProvider).query, 'nan',
        reason: 'typing feeds the provider other screens also read');
    expect(find.text('Nana'), findsOneWidget);
    expect(find.text('Berserk'), findsNothing);
    expect(find.text('Monster'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No manga found.'), findsOneWidget,
        reason: 'a query without hits falls back to the empty state');

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.byType(MangaGridTile), findsNWidgets(3),
        reason: 'clearing the box restores the full grid');
    expect(container.read(libraryFilterProvider).query, '');
  });

  testWidgets(
      'the filter sheet applies status and sort, the badge counts them, '
      'and Reset restores the list', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(backend: _PlainBackend()));
    await tester.pumpAndSettle();
    final container = _containerOf(tester);
    expect(_badgeLabel('2'), findsNothing);

    await tester.tap(find.byTooltip('Sort & filter'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryFilterSheet), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Ongoing'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Title (Z–A)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryFilterSheet), findsNothing);
    expect(
        container.read(libraryFilterProvider).statuses, {MangaStatus.ongoing});
    expect(container.read(libraryFilterProvider).sort, LibrarySort.titleDesc);
    expect(_badgeLabel('2'), findsOneWidget,
        reason: 'status plus non-default sort is two active filters');
    expect(_tileTitles(tester), ['Monster', 'Berserk'],
        reason: 'only ongoing titles, in reverse title order');

    await tester.tap(find.byTooltip('Sort & filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(_tileTitles(tester), ['Berserk', 'Monster', 'Nana']);
    expect(container.read(libraryFilterProvider).activeCount, 0);
    expect(_badgeLabel('2'), findsNothing,
        reason: 'the badge disappears once nothing is active');
  });

  testWidgets('library chips switch which library the grid shows',
      (tester) async {
    _tall(tester);
    final backend = _PlainBackend(
      libraries: const [
        KsLibrary(id: 'a', name: 'Main', mangaCount: 2),
        KsLibrary(id: 'b', name: 'Kids', mangaCount: 1),
      ],
      mangaByLibrary: const {
        'a': [
          KsManga(id: 'm1', title: 'Berserk', genres: ['Action']),
          KsManga(id: 'm2', title: 'Nana', genres: ['Drama']),
        ],
        'b': [
          KsManga(id: 'm3', title: 'Monster', genres: ['Mystery']),
        ],
      },
    );
    await tester.pumpWidget(_app(backend: backend));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Main (2)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Kids (1)'), findsOneWidget);
    expect(_tileTitles(tester), ['Berserk', 'Monster', 'Nana']);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Main (2)'));
    await tester.pumpAndSettle();
    expect(backend.libraryRequests, contains('a'),
        reason: 'the grid refetches for the chosen library');
    expect(_tileTitles(tester), ['Berserk', 'Nana']);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Main (2)'))
            .selected,
        isTrue);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All'))
            .selected,
        isFalse,
        reason: 'the All chip yields selection to the picked library');

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    expect(backend.libraryRequests, contains(null));
    expect(_tileTitles(tester), ['Berserk', 'Monster', 'Nana']);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All'))
            .selected,
        isTrue);
  });

  testWidgets('an empty library says so instead of showing a blank grid',
      (tester) async {
    await tester.pumpWidget(_app(
      backend: _PlainBackend(
        libraries: const [KsLibrary(id: 'all', name: 'All', mangaCount: 0)],
        manga: const [],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No manga found.'), findsOneWidget);
    expect(find.byType(MangaGridTile), findsNothing);
    expect(find.byType(TextField), findsOneWidget,
        reason: 'the search box stays available');
  });

  testWidgets('a capable backend offers discovery, extensions and categories',
      (tester) async {
    _tall(tester);
    final visited = <String>[];
    await tester.pumpWidget(_app(backend: _CapableBackend(), visited: visited));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Recommended for you'), findsOneWidget);
    expect(find.byTooltip('Discover new manga'), findsOneWidget);
    expect(find.byTooltip('Extensions'), findsOneWidget);
    expect(find.byTooltip('Manage categories'), findsOneWidget);

    await tester.tap(find.byTooltip('Recommended for you'));
    await tester.pumpAndSettle();
    expect(visited, ['/recommended'],
        reason: 'the action really routes to the recommended screen');
  });

  testWidgets('a backend without those capabilities hides the actions',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(backend: _PlainBackend()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Recommended for you'), findsNothing);
    expect(find.byTooltip('Discover new manga'), findsNothing);
    expect(find.byTooltip('Extensions'), findsNothing);
    expect(find.byTooltip('Manage categories'), findsNothing);
    expect(find.byTooltip('Sort & filter'), findsOneWidget,
        reason: 'client-side filtering does not depend on the backend');
  });

  testWidgets('tapping a tile opens that title screen', (tester) async {
    _tall(tester);
    final visited = <String>[];
    await tester.pumpWidget(_app(backend: _PlainBackend(), visited: visited));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nana'));
    await tester.pumpAndSettle();

    expect(visited, ['/manga/m2']);
    expect(find.byType(MangaDetailScreen), findsOneWidget);
  });
}
