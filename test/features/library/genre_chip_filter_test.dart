import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/server_backend.dart';
import 'package:kai_shelf/core/providers/backend_providers.dart';
import 'package:kai_shelf/features/library/presentation/library_screen.dart';
import 'package:kai_shelf/features/library/presentation/manga_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory backend: a small library plus detail pages for its titles and
/// one preview-only title that is deliberately absent from the library list.
class _FakeLibraryBackend implements ServerBackend {
  _FakeLibraryBackend({required this.libraryManga, required this.details});

  final List<KsManga> libraryManga;
  final List<KsManga> details;

  @override
  Future<List<KsLibrary>> getLibraries() async => [
        KsLibrary(id: '1', name: 'All', mangaCount: libraryManga.length),
      ];

  @override
  Future<List<KsManga>> getAllManga(
          {String? libraryId, String? searchQuery}) async =>
      libraryManga;

  @override
  Future<KsManga> getMangaDetail(String mangaId) async =>
      details.firstWhere((m) => m.id == mangaId);

  @override
  Future<List<KsChapter>> getChapters(String mangaId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

_FakeLibraryBackend _backend() => _FakeLibraryBackend(
      libraryManga: const [
        KsManga(id: 'm1', title: 'Berserk', genres: ['Action', 'Dark Fantasy']),
        KsManga(id: 'm2', title: 'Nana', genres: ['Drama']),
        KsManga(id: 'm3', title: 'Monster', genres: ['Mystery']),
      ],
      details: const [
        KsManga(id: 'm1', title: 'Berserk', genres: ['Action', 'Dark Fantasy']),
        // Preview-only title: not in the library list, and its genre matches
        // nothing there either.
        KsManga(id: 'm4', title: 'Solaris', genres: ['Sci-Fi']),
      ],
    );

Widget _app({required ServerBackend backend, String initialLocation = '/'}) {
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
    ],
  );
  return ProviderScope(
    overrides: [activeBackendProvider.overrideWithValue(backend)],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// The filter button's badge label sits next to the filter icon.
Finder _badgeLabel() => find.descendant(
    of: find.byTooltip('Sort & filter'), matching: find.text('1'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'tapping a genre chip on the title screen opens the library filtered '
      'by that genre, with the filter badge showing one active filter',
      (tester) async {
    await tester
        .pumpWidget(_app(backend: _backend(), initialLocation: '/manga/m1'));
    await tester.pumpAndSettle();

    // The genre tags are there on the title screen.
    expect(find.text('Action'), findsOneWidget);
    expect(find.text('Dark Fantasy'), findsOneWidget);

    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();

    // We are on the library now, showing only Action titles.
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(MangaDetailScreen), findsNothing);
    expect(find.text('Berserk'), findsOneWidget);
    expect(find.text('Nana'), findsNothing);
    expect(find.text('Monster'), findsNothing);

    // The filter badge reports the genre as one active filter.
    expect(_badgeLabel(), findsOneWidget);
  });

  testWidgets('a genre with no matches shows the normal empty state',
      (tester) async {
    await tester
        .pumpWidget(_app(backend: _backend(), initialLocation: '/manga/m4'));
    await tester.pumpAndSettle();

    expect(find.text('Sci-Fi'), findsOneWidget);
    await tester.tap(find.text('Sci-Fi'));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text('No manga found.'), findsOneWidget);
  });

  testWidgets('clearing the genre in the filter sheet restores the full list',
      (tester) async {
    // A phone-tall window, so the sheet's genre section is on screen.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester
        .pumpWidget(_app(backend: _backend(), initialLocation: '/manga/m1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    expect(find.text('Nana'), findsNothing);

    await tester.tap(find.byTooltip('Sort & filter'));
    await tester.pumpAndSettle();

    // The sheet shows the genre it was handed as an include filter.
    expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Action'))
            .selected,
        isTrue);

    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Berserk'), findsOneWidget);
    expect(find.text('Nana'), findsOneWidget);
    expect(find.text('Monster'), findsOneWidget);
    // Badge is hidden again: nothing active.
    expect(_badgeLabel(), findsNothing);
  });
}
