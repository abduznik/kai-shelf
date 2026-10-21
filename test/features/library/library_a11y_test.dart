// Semantics coverage for the library, title screen and filter sheet
// (issue #16): grid tiles announce as one meaningful unit, icon-only app bar
// buttons announce their purpose, genre chips announce include/exclude, and
// the small title-screen chips keep a 48dp touch target.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/server_backend.dart';
import 'package:kai_shelf/core/providers/backend_providers.dart';
import 'package:kai_shelf/features/library/domain/library_filter.dart';
import 'package:kai_shelf/features/library/presentation/library_screen.dart';
import 'package:kai_shelf/features/library/presentation/manga_detail_screen.dart';
import 'package:kai_shelf/features/library/presentation/widgets/library_filter_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory backend: three library titles with mixed statuses, plus detail
/// pages for the first one.
class _FakeBackend
    implements ServerBackend, SourceCapableBackend, ExtensionCapableBackend {
  @override
  Future<List<KsLibrary>> getLibraries() async =>
      [KsLibrary(id: '1', name: 'All', mangaCount: 3)];

  @override
  Future<List<KsManga>> getAllManga(
          {String? libraryId, String? searchQuery}) async =>
      const [
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
        KsManga(id: 'm3', title: 'Monster', genres: ['Mystery']),
      ];

  @override
  Future<KsManga> getMangaDetail(String mangaId) async => const KsManga(
        id: 'm1',
        title: 'Berserk',
        genres: ['Action', 'Dark Fantasy'],
        status: MangaStatus.ongoing,
        inLibrary: true,
      );

  @override
  Future<List<KsChapter>> getChapters(String mangaId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Widget _app({String initialLocation = '/library'}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
          path: '/', builder: (_, __) => const Scaffold(body: Text('home'))),
      GoRoute(path: '/library', builder: (_, __) => const LibraryScreen()),
      GoRoute(
        path: '/manga/:mangaId',
        builder: (_, state) =>
            MangaDetailScreen(mangaId: state.pathParameters['mangaId']!),
      ),
      GoRoute(path: '/recommended', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/discover', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/extensions', builder: (_, __) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [activeBackendProvider.overrideWithValue(_FakeBackend())],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('grid tiles announce title and status as one tappable unit',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // Cover, title and status arrive as a single announcement instead of a
    // bare image and a bare title.
    expect(find.bySemanticsLabel('Berserk, Ongoing'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Berserk, Ongoing')),
      isSemantics(
          label: 'Berserk, Ongoing', isButton: true, hasTapAction: true),
    );
    // Titles without a known status still announce their title as one unit.
    expect(find.bySemanticsLabel('Monster'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('icon-only library app bar buttons announce their purpose',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // The filter badge count rides along in the same announcement.
    expect(find.bySemanticsLabel(RegExp(r'^Sort & filter')), findsOneWidget);
    expect(find.bySemanticsLabel('Recommended for you'), findsOneWidget);
    expect(find.bySemanticsLabel('Discover new manga'), findsOneWidget);
    expect(find.bySemanticsLabel('Extensions'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('filter sheet genre chips announce include and exclude',
      (tester) async {
    final handle = tester.ensureSemantics();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LibraryFilterSheet(
          initial: LibraryFilter(),
          genres: ['Action', 'Romance'],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Off: neither included nor excluded, not selected.
    expect(tester.getSemantics(find.bySemanticsLabel('Action')).value, isEmpty);

    // First tap includes: the chip reads as selected.
    await tester.tap(find.widgetWithText(FilterChip, 'Action'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.bySemanticsLabel('Action')),
        isSemantics(label: 'Action', isSelected: true));

    // Second tap excludes: an unselected chip must still say that the genre
    // is being filtered out, not look identical to an untouched one.
    await tester.tap(find.widgetWithText(FilterChip, 'Action'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Action')),
      isSemantics(label: 'Action', value: 'Excluded', isSelected: false),
    );
    handle.dispose();
  });

  testWidgets(
      'title screen genre chips keep a 48dp touch target and the app bar '
      'icon buttons are labelled', (tester) async {
    final handle = tester.ensureSemantics();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(initialLocation: '/manga/m1'));
    await tester.pumpAndSettle();

    final chip = tester.getRect(find.widgetWithText(FilterChip, 'Action'));
    expect(chip.height, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel('Action'), findsOneWidget);

    // Icon-only app bar buttons on the title screen.
    expect(find.bySemanticsLabel('Remove from library'), findsOneWidget);
    expect(find.bySemanticsLabel('Batch download'), findsOneWidget);
    expect(find.bySemanticsLabel('Newest first'), findsOneWidget);
    handle.dispose();
  });
}
