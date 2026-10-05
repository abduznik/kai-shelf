import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/providers/backend_providers.dart';
import 'package:kai_shelf/features/extensions/presentation/extensions_screen.dart';

import 'fake_backend.dart';

Widget _app(FakeCatalogBackend backend) => ProviderScope(
      overrides: [activeBackendProvider.overrideWithValue(backend)],
      child: const MaterialApp(home: ExtensionsScreen()),
    );

void main() {
  FakeCatalogBackend backend() => FakeCatalogBackend(extensions: [
        const KsExtension(pkgName: 'p.alpha', name: 'Alpha', lang: 'en'),
        const KsExtension(
            pkgName: 'p.beta', name: 'Beta', lang: 'en', isInstalled: true),
        const KsExtension(
            pkgName: 'p.gamma',
            name: 'Gamma',
            lang: 'fr',
            isInstalled: true,
            hasUpdate: true),
        const KsExtension(
            pkgName: 'p.nsfw',
            name: 'Spicy',
            lang: 'en',
            contentWarning: ContentWarning.nsfw),
      ]);

  testWidgets('installs, updates and uninstalls extensions', (tester) async {
    final b = backend();
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Install').first);
    await tester.pumpAndSettle();
    expect(b.calls, contains('install:p.alpha'));

    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pumpAndSettle();
    expect(b.calls, contains('update:p.gamma'));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Uninstall').first);
    await tester.pumpAndSettle();
    expect(b.calls.any((c) => c.startsWith('uninstall:')), isTrue);
  });

  testWidgets('search, status and NSFW filters narrow the list',
      (tester) async {
    await tester.pumpWidget(_app(backend()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'gam');
    await tester.pumpAndSettle();
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Not installed'));
    await tester.pumpAndSettle();
    expect(find.text('Spicy'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    await tester.tap(find.text('Hide NSFW'));
    await tester.pumpAndSettle();
    expect(find.text('Spicy'), findsNothing);
  });

  testWidgets('refresh asks the server to re-read repositories',
      (tester) async {
    final b = backend();
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh from repositories'));
    await tester.pumpAndSettle();
    expect(b.calls, contains('refresh'));
  });

  testWidgets('adds a repository from the repositories sheet', (tester) async {
    final b = backend();
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Repositories'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Repository index URL'),
        'https://example.com/index.json');
    await tester.tap(find.byTooltip('Add repository'));
    await tester.pumpAndSettle();
    expect(b.calls, contains('addRepo:https://example.com/index.json'));
    expect(b.calls, contains('refresh'));
    expect(find.text('https://example.com/index.json'), findsOneWidget);
  });

  testWidgets('rejects a non-URL repository', (tester) async {
    final b = backend();
    await tester.pumpWidget(_app(b));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Repositories'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Repository index URL'), 'nope');
    await tester.tap(find.byTooltip('Add repository'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a full http(s) index URL.'), findsOneWidget);
    expect(b.calls.where((c) => c.startsWith('addRepo')), isEmpty);
  });
}
