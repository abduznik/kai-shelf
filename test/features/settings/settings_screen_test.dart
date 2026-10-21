import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kai_shelf/core/providers/incognito_provider.dart';
import 'package:kai_shelf/core/providers/reader_prefs_provider.dart';
import 'package:kai_shelf/core/providers/theme_provider.dart';
import 'package:kai_shelf/features/settings/presentation/settings_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings screen (#12): theme override, reading defaults, version row and
/// the Downloads link, plus a regression guard on the incognito switch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, child) => MaterialApp.router(
            // Mirrors main.dart: the app theme follows the persisted choice.
            theme: ThemeData(
              colorSchemeSeed: Colors.indigo,
              useMaterial3: true,
              brightness: Brightness.light,
            ),
            darkTheme: ThemeData(
              colorSchemeSeed: Colors.indigo,
              useMaterial3: true,
              brightness: Brightness.dark,
            ),
            themeMode: ref.watch(themeModeProvider),
            routerConfig: GoRouter(
              initialLocation: '/settings',
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (context, state) => const SettingsScreen(),
                ),
                GoRoute(
                  path: '/downloads',
                  builder: (context, state) => const _DownloadsStub(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));

  testWidgets('theme choice is offered and a Dark pick shows up immediately',
      (tester) async {
    await pumpSettings(tester);

    final themeTile = find.widgetWithText(ListTile, 'Theme');
    expect(themeTile, findsOneWidget,
        reason: 'settings must expose a theme override row');
    final initial = tester.widget<ListTile>(themeTile);
    expect((initial.subtitle as Text).data, 'System');

    await tester.tap(themeTile);
    await tester.pumpAndSettle();
    final options = find.descendant(
      of: find.byType(SimpleDialog),
      matching: find.byType(SimpleDialogOption),
    );
    expect(options, findsNWidgets(3),
        reason: 'the dialog must offer System, Light and Dark');
    for (final label in const ['System', 'Light', 'Dark']) {
      expect(
        find.descendant(
            of: find.byType(SimpleDialog), matching: find.text(label)),
        findsOneWidget,
        reason: 'the dialog must offer $label',
      );
    }

    await tester.tap(find.descendant(
        of: find.byType(SimpleDialog), matching: find.text('Dark')));
    await tester.pumpAndSettle();

    final updated = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Theme'),
    );
    expect((updated.subtitle as Text).data, 'Dark',
        reason: 'the choice must take effect immediately');

    expect(containerOf(tester).read(themeModeProvider), ThemeMode.dark,
        reason: 'the provider drives the app-wide theme');
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
        reason: 'MaterialApp must honour the choice in the same frame');
  });

  testWidgets('reading defaults drive the global reader providers',
      (tester) async {
    await pumpSettings(tester);
    final container = containerOf(tester);

    final modeTile = find.widgetWithText(ListTile, 'Reading mode');
    final directionTile = find.widgetWithText(ListTile, 'Reading direction');
    expect(modeTile, findsOneWidget);
    expect(directionTile, findsOneWidget);

    await tester.tap(modeTile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Webtoon'));
    await tester.pumpAndSettle();
    expect(container.read(readerModeProvider), ReaderMode.webtoon);
    expect(await loadReaderMode(), ReaderMode.webtoon,
        reason: 'the global default must persist');

    await tester.tap(directionTile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Right to left'));
    await tester.pumpAndSettle();
    expect(container.read(readingDirectionProvider), ReadingDirection.rtl);
    expect(await loadReadingDirection(), ReadingDirection.rtl,
        reason: 'the global default must persist');
  });

  testWidgets('version row shows version and build number', (tester) async {
    await pumpSettings(tester);

    final row = find.widgetWithText(ListTile, 'Version');
    await tester.scrollUntilVisible(row, 300);
    expect(row, findsOneWidget, reason: 'settings must surface the version');
    expect(find.text('1.2.0+7'), findsOneWidget,
        reason: 'version plus build number must be visible');
  });

  testWidgets('Downloads tile opens the downloads route', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Downloads'));
    await tester.pumpAndSettle();
    expect(find.byType(_DownloadsStub), findsOneWidget,
        reason: 'the Downloads tile must push /downloads');
  });

  testWidgets('incognito switch still toggles', (tester) async {
    await pumpSettings(tester);
    final container = containerOf(tester);

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(container.read(incognitoProvider), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(incognitoPrefKey), isTrue);
  });
}

class _DownloadsStub extends StatelessWidget {
  const _DownloadsStub();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('downloads route reached')));
}
