import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/providers/reader_prefs_provider.dart';
import 'package:kai_shelf/features/reader/presentation/widgets/reader_controls_overlay.dart';

Widget _overlay({ReaderMode mode = ReaderMode.paged}) => MaterialApp(
      home: Scaffold(
        body: ReaderControlsOverlay(
          visible: true,
          currentPage: 0,
          totalPages: 10,
          mode: mode,
          onModeChanged: (_) {},
          onClose: () {},
        ),
      ),
    );

void main() {
  testWidgets('offers a reading-direction control in paged mode',
      (tester) async {
    await tester.pumpWidget(_overlay());
    expect(find.byTooltip('Read right to left'), findsOneWidget);
  });

  testWidgets('offers a reset-to-default control', (tester) async {
    await tester.pumpWidget(_overlay());
    expect(find.byTooltip('Reset to default'), findsOneWidget);
  });

  testWidgets('hides the direction control in webtoon mode', (tester) async {
    await tester.pumpWidget(_overlay(mode: ReaderMode.webtoon));
    expect(find.byTooltip('Read right to left'), findsNothing);
    expect(find.byTooltip('Read left to right'), findsNothing);
  });
}
