// Settings screen connection rows (issue #18): the capability-gated source,
// category and extension links, the not-connected note, and the disconnect
// flow that forgets the stored session and routes home. Theme, reading
// defaults, the incognito switch and the update rows are covered by
// settings_screen_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/server_backend.dart';
import 'package:kai_shelf/core/providers/backend_providers.dart';
import 'package:kai_shelf/core/update/update_check_provider.dart';
import 'package:kai_shelf/features/settings/presentation/settings_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A backend with no optional capabilities: only the shared rows may show.
class _PlainBackend implements ServerBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A backend with every optional capability, whose categories are called
/// "collections" (Komga-style), so the tile must wear that noun.
class _CapableBackend extends _PlainBackend
    implements
        SourceCapableBackend,
        CategoryCapableBackend,
        ExtensionCapableBackend {
  @override
  String get categoryNoun => 'collection';

  @override
  bool get canReorderCategories => false;

  @override
  bool get canCreateEmptyCategory => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final _connection = ServerConnectionInfo(
  serverId: 'srv',
  displayName: 'srv',
  baseUrl: Uri.parse('http://example.com'),
  type: BackendType.komga,
);

Future<void> _pumpSettings(
  WidgetTester tester, {
  ServerBackend? backend,
  required List<String> visited,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Opening Settings fires the opportunistic update check; keep the
        // test offline and deterministic.
        updateHttpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('', 500)),
        ),
        if (backend != null) ...[
          activeBackendProvider.overrideWithValue(backend),
          activeConnectionProvider.overrideWith((ref) => _connection),
        ],
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/settings',
          routes: [
            GoRoute(
                path: '/',
                builder: (_, __) => const Scaffold(body: Text('home'))),
            GoRoute(
                path: '/settings', builder: (_, __) => const SettingsScreen()),
            for (final path in const [
              '/discover',
              '/categories',
              '/extensions',
              '/downloads',
            ])
              GoRoute(
                path: path,
                builder: (context, _) {
                  visited.add(path);
                  return Scaffold(
                    body: TextButton(
                      onPressed: context.pop,
                      child: const Text('back'),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A phone-tall window, so the whole settings list is on screen.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Kai-Shelf',
      packageName: 'kai_shelf',
      version: '1.2.0',
      buildNumber: '7',
      buildSignature: '',
    );
  });

  testWidgets(
      'a capable backend exposes its source, category and extension '
      'links', (tester) async {
    _tall(tester);
    final visited = <String>[];
    await _pumpSettings(tester, backend: _CapableBackend(), visited: visited);

    expect(find.widgetWithText(ListTile, 'Sources'), findsOneWidget,
        reason: 'source browsing is offered where the backend supports it');
    expect(find.widgetWithText(ListTile, 'Collections'), findsOneWidget,
        reason: 'the category tile wears the backend\'s own noun');
    expect(find.widgetWithText(ListTile, 'Extensions'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Disconnect'), findsOneWidget);
    expect(find.text('Connect to a server to manage sources and extensions.'),
        findsNothing);

    await tester.tap(find.widgetWithText(ListTile, 'Sources'));
    await tester.pumpAndSettle();
    expect(visited, ['/discover']);
    await tester.tap(find.widgetWithText(TextButton, 'back'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Collections'));
    await tester.pumpAndSettle();
    expect(visited, ['/discover', '/categories']);
    await tester.tap(find.widgetWithText(TextButton, 'back'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Extensions'));
    await tester.pumpAndSettle();
    expect(visited, ['/discover', '/categories', '/extensions']);
  });

  testWidgets('a backend without those capabilities hides the links',
      (tester) async {
    _tall(tester);
    final visited = <String>[];
    await _pumpSettings(tester, backend: _PlainBackend(), visited: visited);

    expect(find.widgetWithText(ListTile, 'Sources'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Collections'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Extensions'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Downloads'), findsOneWidget,
        reason: 'downloads are backend-independent');
    expect(find.widgetWithText(ListTile, 'Disconnect'), findsOneWidget);
    expect(find.text('Connect to a server to manage sources and extensions.'),
        findsNothing);
    expect(visited, isEmpty);
  });

  testWidgets(
      'without a connection settings points at connecting instead of '
      'disconnecting', (tester) async {
    _tall(tester);
    final visited = <String>[];
    await _pumpSettings(tester, visited: visited);

    expect(find.text('Connect to a server to manage sources and extensions.'),
        findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Disconnect'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Sources'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Downloads'), findsOneWidget);
  });

  testWidgets('disconnect forgets the stored session and routes home',
      (tester) async {
    _tall(tester);
    const storage = FlutterSecureStorage();
    const sessionKey = 'session.activeConnection';
    FlutterSecureStorage.setMockInitialValues({sessionKey: 'seeded-session'});
    expect(await storage.read(key: sessionKey), 'seeded-session',
        reason: 'the session really is on disk before the tap');

    final visited = <String>[];
    await _pumpSettings(tester, backend: _PlainBackend(), visited: visited);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));

    final disconnect = find.widgetWithText(ListTile, 'Disconnect');
    expect(disconnect, findsOneWidget);
    expect((tester.widget<ListTile>(disconnect).subtitle as Text).data,
        _connection.baseUrl.toString(),
        reason: 'the tile names the server it will drop');

    await tester.tap(disconnect);
    await tester.pumpAndSettle();

    expect(container.read(activeConnectionProvider), isNull,
        reason: 'the active connection must be cleared');
    expect(await storage.read(key: sessionKey), isNull,
        reason: 'the stored session must be wiped');
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text('home'), findsOneWidget,
        reason: 'disconnecting lands back on the connect screen');
    expect(visited, isEmpty);
  });
}
