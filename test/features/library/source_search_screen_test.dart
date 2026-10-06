import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/providers/backend_providers.dart';
import 'package:kai_shelf/features/library/presentation/source_search_screen.dart';

import '../extensions/fake_backend.dart';

Widget _app(FakeCatalogBackend backend) => ProviderScope(
      overrides: [activeBackendProvider.overrideWithValue(backend)],
      child: const MaterialApp(
        home: SourceSearchScreen(sourceId: '1', sourceName: 'Alpha'),
      ),
    );

/// The grid's trailing spinner animates forever while more pages exist, so
/// pumpAndSettle would never return.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('shows popular first, then pages in on scroll', (tester) async {
    final b = FakeCatalogBackend(pageSize: 12);
    await tester.pumpWidget(_app(b));
    await _settle(tester);

    expect(b.calls.first, 'browse:popular:1');
    expect(find.text('Title 0'), findsOneWidget);

    await tester.drag(find.byType(GridView), const Offset(0, -3000));
    await _settle(tester);
    expect(b.calls, contains('browse:popular:2'));
  });

  testWidgets('submitting a query switches to search mode', (tester) async {
    final b = FakeCatalogBackend();
    await tester.pumpWidget(_app(b));
    await _settle(tester);

    await tester.enterText(find.byType(TextField), 'berserk');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);

    expect(b.lastMode, SourceBrowseMode.search);
    expect(b.lastQuery, 'berserk');
  });

  testWidgets('latest tab browses latest', (tester) async {
    final b = FakeCatalogBackend();
    await tester.pumpWidget(_app(b));
    await _settle(tester);
    await tester.tap(find.text('Latest'));
    await _settle(tester);
    expect(b.lastMode, SourceBrowseMode.latest);
  });

  testWidgets('filter sheet sends nested tri-state and sort changes',
      (tester) async {
    final b = FakeCatalogBackend();
    await tester.pumpWidget(_app(b));
    await _settle(tester);

    await tester.tap(find.byTooltip('Filters'));
    await _settle(tester);
    await tester.tap(find.text('Genres'));
    await _settle(tester);
    await tester.tap(find.text('Drama')); // ignore -> include
    await _settle(tester);
    await tester.tap(find.text('Apply'));
    await _settle(tester);

    expect(b.lastMode, SourceBrowseMode.search);
    final change = b.lastFilters!.single;
    expect(change.path, [1, 1]);
    expect(change.triState, KsTriState.include);
  });

  testWidgets('tapping a result adds it to the library and toggles back',
      (tester) async {
    final b = FakeCatalogBackend();
    await tester.pumpWidget(_app(b));
    await _settle(tester);

    await tester.tap(find.text('Title 1'));
    await _settle(tester);
    expect(b.calls, contains('add:m1'));
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.tap(find.text('Title 1'));
    await _settle(tester);
    expect(b.calls, contains('remove:m1'));
    expect(find.byIcon(Icons.favorite), findsNothing);
  });
}
