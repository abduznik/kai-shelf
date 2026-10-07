import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/server_backend.dart';
import 'package:kai_shelf/core/providers/backend_providers.dart';
import 'package:kai_shelf/core/providers/incognito_provider.dart';
import 'package:kai_shelf/features/history/presentation/history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serves a fixed history; everything else is unused by the screen.
class FakeHistoryBackend implements ServerBackend, HistoryCapableBackend {
  FakeHistoryBackend(this.entries);

  final List<KsHistoryEntry> entries;

  int calls = 0;

  @override
  Future<List<KsHistoryEntry>> getHistory(
      {int limit = 50, int offset = 0}) async {
    calls++;
    return entries.skip(offset).take(limit).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A backend with no history support.
class PlainBackend implements ServerBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final _now = DateTime(2026, 10, 7, 12);

KsHistoryEntry _entry(String id, DateTime at,
        {bool read = false, double? page, int? pages}) =>
    KsHistoryEntry(
      mangaId: 'm$id',
      mangaTitle: 'Manga $id',
      chapterId: 'c$id',
      chapterTitle: 'Chapter $id',
      lastReadAt: at,
      lastPageRead: page,
      pageCount: pages,
      read: read,
    );

final _connection = ServerConnectionInfo(
  serverId: 'srv',
  displayName: 'srv',
  baseUrl: Uri.parse('http://example.com'),
  type: BackendType.suwayomi,
);

Widget _app(ServerBackend backend, List<String> visited) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => HistoryScreen(now: _now)),
      GoRoute(
        path: '/reader/:mangaId/:chapterId',
        builder: (context, state) {
          visited.add(state.uri.path);
          return Scaffold(
            body: TextButton(
                onPressed: () => context.pop(), child: const Text('back')),
          );
        },
      ),
      GoRoute(
        path: '/manga/:mangaId',
        builder: (_, state) {
          visited.add(state.uri.path);
          return const Scaffold(body: Text('detail'));
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      activeBackendProvider.overrideWithValue(backend),
      activeConnectionProvider.overrideWith((ref) => _connection),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  FakeHistoryBackend backend() => FakeHistoryBackend([
        _entry('1', DateTime(2026, 10, 7, 11), page: 6, pages: 24),
        _entry('2', DateTime(2026, 10, 7, 9), read: true, pages: 10),
        _entry('3', DateTime(2026, 10, 6, 20), page: 0, pages: 8),
        _entry('4', DateTime(2026, 10, 1, 8)),
      ]);

  testWidgets('groups by day and shows cover-less rows with progress',
      (tester) async {
    await tester.pumpWidget(_app(backend(), []));
    await tester.pump();
    await tester.pump();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Thu, 1 Oct'), findsOneWidget);
    expect(find.text('Manga 1'), findsOneWidget);
    expect(find.textContaining('Page 7 of 24'), findsOneWidget);
    expect(find.textContaining('Finished'), findsOneWidget);
    expect(find.textContaining('Page 1 of 8'), findsOneWidget);
    expect(find.textContaining('Started'), findsOneWidget);
  });

  testWidgets('tapping a row opens the reader at that chapter', (tester) async {
    final visited = <String>[];
    await tester.pumpWidget(_app(backend(), visited));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Manga 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(visited, ['/reader/m2/c2']);
  });

  testWidgets('refetches when coming back from the reader', (tester) async {
    final b = backend();
    await tester.pumpWidget(_app(b, []));
    await tester.pump();
    await tester.pump();
    expect(b.calls, 1);

    await tester.tap(find.text('Manga 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(b.calls, 2);
  });

  testWidgets('menu opens the manga detail', (tester) async {
    final visited = <String>[];
    await tester.pumpWidget(_app(backend(), visited));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('More').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Open manga'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(visited, ['/manga/m1']);
  });

  testWidgets('remove hides one row and keeps it hidden on reload',
      (tester) async {
    final b = backend();
    await tester.pumpWidget(_app(b, []));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('More').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Remove from history'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Manga 1'), findsNothing);
    expect(find.text('Manga 2'), findsOneWidget);

    // A fresh screen (new provider scope) reads the hidden set from disk.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(b, []));
    await tester.pump();
    await tester.pump();
    expect(find.text('Manga 1'), findsNothing);
    expect(find.text('Manga 2'), findsOneWidget);
  });

  testWidgets('clear history empties the list after confirming',
      (tester) async {
    await tester.pumpWidget(_app(backend(), []));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Clear history'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Clear history?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Nothing read yet'), findsOneWidget);
    expect(find.text('Manga 1'), findsNothing);
  });

  testWidgets('says so when the server has no history support', (tester) async {
    await tester.pumpWidget(_app(PlainBackend(), []));
    await tester.pump();
    expect(find.textContaining('does not provide reading history'),
        findsOneWidget);
  });

  testWidgets('shows the incognito badge only while incognito is on',
      (tester) async {
    final container = ProviderContainer(overrides: [
      activeBackendProvider.overrideWithValue(backend()),
      activeConnectionProvider.overrideWith((ref) => _connection),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: HistoryScreen(now: _now)),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Incognito'), findsNothing);

    await container.read(incognitoProvider.notifier).setEnabled(true);
    await tester.pump();
    expect(find.text('Incognito'), findsOneWidget);
  });
}
