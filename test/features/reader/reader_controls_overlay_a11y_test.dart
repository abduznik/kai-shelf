// Semantics coverage for the reader controls overlay (issue #16).
//
// Every interactive control in the overlay must announce role, label and
// state: the page slider has to say which page it is on, icon-only buttons
// need labels, and the direction/reset controls have to expose the current
// state rather than only the action.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/providers/reader_prefs_provider.dart';
import 'package:kai_shelf/features/reader/presentation/widgets/reader_controls_overlay.dart';

Widget _overlay({
  int currentPage = 0,
  int totalPages = 10,
  bool visible = true,
  ReaderMode mode = ReaderMode.paged,
  ReadingDirection direction = ReadingDirection.ltr,
  bool hasOverride = false,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ReaderControlsOverlay(
          visible: visible,
          currentPage: currentPage,
          totalPages: totalPages,
          mode: mode,
          direction: direction,
          hasOverride: hasOverride,
          onModeChanged: (_) {},
          onClose: () {},
          onDirectionChanged: (_) {},
          onResetToDefault: hasOverride ? () {} : null,
        ),
      ),
    );

void main() {
  testWidgets('page slider announces the current page out of the total',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_overlay(currentPage: 3, totalPages: 12));
    await tester.pumpAndSettle();

    // A raw percentage ("27%") tells a screen-reader user nothing about
    // where they are in the chapter.
    expect(
      tester.semantics.simulatedAccessibilityTraversal(),
      contains(isSemantics(isSlider: true, value: 'Page 4 of 12')),
    );
    handle.dispose();
  });

  testWidgets('icon-only overlay buttons announce their purpose',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_overlay());
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expect(find.bySemanticsLabel('Previous chapter'), findsOneWidget);
    expect(find.bySemanticsLabel('Next chapter'), findsOneWidget);
    expect(find.bySemanticsLabel('Paged view'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the direction control announces the current direction',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_overlay(direction: ReadingDirection.ltr));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Reading direction: left to right'),
        findsOneWidget);

    await tester.pumpWidget(_overlay(direction: ReadingDirection.rtl));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Reading direction: right to left'),
        findsOneWidget);
    handle.dispose();
  });

  testWidgets('the reset control announces whether there is anything to reset',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_overlay(hasOverride: false));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Nothing to reset'), findsOneWidget);

    await tester.pumpWidget(_overlay(hasOverride: true));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Reset to default'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the mode control announces the mode it is in', (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_overlay(mode: ReaderMode.paged));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Paged view'), findsOneWidget);

    await tester.pumpWidget(_overlay(mode: ReaderMode.webtoon));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Continuous scroll'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the hidden controls are not exposed to screen readers',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_overlay(visible: true));
    await tester.pumpAndSettle();
    expect(
      tester.semantics.simulatedAccessibilityTraversal(),
      contains(isSemantics(tooltip: 'Previous chapter')),
    );

    await tester.pumpWidget(_overlay(visible: false));
    await tester.pumpAndSettle();
    expect(
      tester.semantics.simulatedAccessibilityTraversal(),
      isNot(contains(isSemantics(tooltip: 'Previous chapter'))),
    );
    handle.dispose();
  });
}
