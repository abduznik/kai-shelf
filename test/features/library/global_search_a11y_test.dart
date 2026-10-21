// Semantics coverage for the global search filter chips (issue #16): the
// NSFW and language chips must announce their selected state.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/providers/backend_providers.dart';
import 'package:kai_shelf/features/library/presentation/global_search_screen.dart';

import '../extensions/fake_backend.dart';

/// One English and one French source, so the language chips have something
/// to select.
class _SearchBackend extends FakeCatalogBackend {
  @override
  Future<List<KsSource>> getSources() async => const [
        KsSource(id: '1', name: 'Alpha', lang: 'en'),
        KsSource(id: '2', name: 'Beta', lang: 'fr'),
      ];
}

/// Section spinners animate while sources answer, so pumpAndSettle would
/// never return.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
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

  testWidgets('filter chips announce their selected state', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(ProviderScope(
      overrides: [activeBackendProvider.overrideWithValue(_SearchBackend())],
      child: const MaterialApp(home: GlobalSearchScreen()),
    ));
    await _settle(tester);

    // NSFW is hidden by default; no language is picked yet.
    expect(
      tester.semantics.simulatedAccessibilityTraversal(),
      contains(
          isSemantics(label: 'Hide NSFW', isSelected: true, isButton: true)),
    );
    expect(
      tester.semantics.simulatedAccessibilityTraversal(),
      isNot(contains(isSemantics(label: 'EN', isSelected: true))),
    );

    // Picking EN flips the chip to selected and must say so.
    await tester.tap(find.widgetWithText(FilterChip, 'EN'));
    await _settle(tester);
    expect(
      tester.semantics.simulatedAccessibilityTraversal(),
      contains(isSemantics(label: 'EN', isSelected: true, isButton: true)),
    );
    expect(
      tester.semantics.simulatedAccessibilityTraversal(),
      isNot(contains(isSemantics(label: 'FR', isSelected: true))),
    );
    handle.dispose();
  });
}
