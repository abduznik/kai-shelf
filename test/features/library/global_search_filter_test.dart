import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/providers/backend_providers.dart';
import 'package:kai_shelf/features/library/presentation/global_search_screen.dart';

import '../extensions/fake_backend.dart';

/// Two English sources (one of them NSFW) plus French and Japanese ones, so
/// the language and NSFW chips each have something to hide.
class _FilterBackend extends FakeCatalogBackend {
  @override
  Future<List<KsSource>> getSources() async => const [
        KsSource(id: '1', name: 'Alpha', lang: 'en'),
        KsSource(id: '2', name: 'Beta', lang: 'fr'),
        KsSource(id: '3', name: 'Gamma', lang: 'ja'),
        KsSource(
          id: '4',
          name: 'Delta',
          lang: 'en',
          contentWarning: ContentWarning.nsfw,
        ),
      ];
}

Widget _app(_FilterBackend backend) => ProviderScope(
      overrides: [activeBackendProvider.overrideWithValue(backend)],
      child: const MaterialApp(home: GlobalSearchScreen()),
    );

/// Section spinners animate while sources answer, so pumpAndSettle would
/// never return.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await _settle(tester);
}

void main() {
  // Four stacked sections don't fit the default 800x600 test viewport, and
  // the results ListView builds children lazily — give it room instead of
  // scrolling, so every section can be asserted directly.
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 1.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  testWidgets('language chip re-filters the results already on screen',
      (tester) async {
    await tester.pumpWidget(_app(_FilterBackend()));
    await _settle(tester);
    await _search(tester, 'naruto');

    // Every safe source answered; the NSFW one is hidden by default.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('Delta'), findsNothing);

    // Selecting EN narrows the live results without retyping the query.
    await tester.tap(find.widgetWithText(FilterChip, 'EN'));
    await _settle(tester);
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'EN')).selected,
      isTrue,
    );
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Gamma'), findsNothing);

    // Deselecting restores the sections that dropped out.
    await tester.tap(find.widgetWithText(FilterChip, 'EN'));
    await _settle(tester);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
  });

  testWidgets('NSFW chip re-filters the results already on screen',
      (tester) async {
    await tester.pumpWidget(_app(_FilterBackend()));
    await _settle(tester);
    await _search(tester, 'naruto');
    expect(find.text('Delta'), findsNothing);

    // Un-hiding NSFW brings the hidden source in...
    await tester.tap(find.widgetWithText(FilterChip, 'Hide NSFW'));
    await _settle(tester);
    expect(find.text('Delta'), findsOneWidget);

    // ...and hiding it again takes it back out.
    await tester.tap(find.widgetWithText(FilterChip, 'Hide NSFW'));
    await _settle(tester);
    expect(find.text('Delta'), findsNothing);
  });

  testWidgets('a new search honors the chips without starting one itself',
      (tester) async {
    await tester.pumpWidget(_app(_FilterBackend()));
    await _settle(tester);

    // Toggling a chip before any search must not fire a search on its own.
    await tester.tap(find.widgetWithText(FilterChip, 'EN'));
    await _settle(tester);
    expect(find.text('Search every installed source at once.'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);

    // But the next query runs against whatever the chips are set to.
    await _search(tester, 'naruto');
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
    expect(find.text('Gamma'), findsNothing);
    expect(find.text('Delta'), findsNothing);
  });
}
