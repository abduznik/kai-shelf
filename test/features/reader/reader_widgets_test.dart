import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/providers/reader_prefs_provider.dart';
import 'package:kai_shelf/features/reader/presentation/paged_reader_view.dart';
import 'package:kai_shelf/features/reader/presentation/reader_jump_controller.dart';
import 'package:kai_shelf/features/reader/presentation/webtoon_reader_view.dart';
import 'package:kai_shelf/features/reader/presentation/widgets/next_chapter_prompt.dart';
import 'package:kai_shelf/features/reader/presentation/widgets/reader_controls_overlay.dart';

Widget _overlay({
  int currentPage = 0,
  int totalPages = 10,
  ValueChanged<int>? onPageSelected,
  VoidCallback? onPrevious,
  VoidCallback? onNext,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ReaderControlsOverlay(
          visible: true,
          currentPage: currentPage,
          totalPages: totalPages,
          mode: ReaderMode.paged,
          onModeChanged: (_) {},
          onClose: () {},
          onPageSelected: onPageSelected,
          onPreviousChapter: onPrevious,
          onNextChapter: onNext,
        ),
      ),
    );

// Local pages with missing files render the error icon, so no network or
// image plugins are involved.
List<KsPage> _pages(int n) => [
      for (var i = 0; i < n; i++)
        KsPage(index: i, imageUrl: '', localPath: '/nonexistent/$i.jpg'),
    ];

// 1x1 PNG; fitWidth makes every page a square as wide as the viewport, so
// page heights are known without a network.
final _tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  group('WebtoonReaderView', () {
    late Directory dir;
    late List<KsPage> pages;

    setUpAll(() {
      dir = Directory.systemTemp.createTempSync('kai_webtoon_');
      pages = [
        for (var i = 0; i < 10; i++)
          KsPage(
            index: i,
            imageUrl: '',
            localPath:
                (File('${dir.path}/$i.png')..writeAsBytesSync(_tinyPng)).path,
          ),
      ];
    });
    tearDownAll(() => dir.deleteSync(recursive: true));

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    testWidgets('opens on the initial page and jumps on request',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final controller = ReaderJumpController();
      final reported = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: WebtoonReaderView(
          pages: pages,
          initialPage: 5,
          jumpController: controller,
          onPageChanged: reported.add,
        ),
      ));
      await settle(tester);
      expect(reported.last, 5);

      controller.jumpTo(8);
      await settle(tester);
      expect(reported.last, 8);

      controller.jumpTo(0);
      await settle(tester);
      expect(reported.last, 0);
    });
  });

  group('page slider', () {
    testWidgets('shows current / total', (tester) async {
      await tester.pumpWidget(_overlay(currentPage: 3, totalPages: 12));
      expect(find.text('4 / 12'), findsOneWidget);
    });

    testWidgets('dragging to the end jumps to the last page', (tester) async {
      int? selected;
      await tester.pumpWidget(_overlay(onPageSelected: (p) => selected = p));

      await tester.drag(find.byType(Slider), const Offset(2000, 0));
      await tester.pump();
      expect(selected, 9);
      expect(find.text('10 / 10'), findsOneWidget);
    });

    testWidgets('tapping the middle of the track jumps there', (tester) async {
      int? selected;
      await tester.pumpWidget(_overlay(onPageSelected: (p) => selected = p));

      await tester.tap(find.byType(Slider));
      await tester.pump();
      expect(selected, inInclusiveRange(3, 6));
    });
  });

  group('chapter buttons', () {
    testWidgets('are disabled when there is no neighbour', (tester) async {
      await tester.pumpWidget(_overlay());
      expect(
          tester
              .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.skip_next))
              .onPressed,
          isNull);
      expect(
          tester
              .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.skip_previous))
              .onPressed,
          isNull);
    });

    testWidgets('fire their callbacks when enabled', (tester) async {
      var next = 0, prev = 0;
      await tester
          .pumpWidget(_overlay(onNext: () => next++, onPrevious: () => prev++));
      await tester.tap(find.byTooltip('Next chapter'));
      await tester.tap(find.byTooltip('Previous chapter'));
      expect((next, prev), (1, 1));
    });

    testWidgets('end-of-chapter prompt opens the next chapter', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: NextChapterPrompt(onPressed: () => tapped = true))));
      await tester.tap(find.text('Next chapter'));
      expect(tapped, isTrue);
    });
  });

  group('PagedReaderView', () {
    testWidgets('opens on the initial page and obeys the jump controller',
        (tester) async {
      final controller = ReaderJumpController();
      final reported = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: PagedReaderView(
          pages: _pages(8),
          initialPage: 5,
          jumpController: controller,
          onPageChanged: reported.add,
        ),
      ));
      await tester.pump();
      final view = tester.widget<PageView>(find.byType(PageView));
      expect(view.controller!.page, 5);

      controller.jumpTo(2);
      await tester.pump();
      expect(view.controller!.page, 2);
      expect(reported, contains(2));

      controller.jumpTo(99);
      await tester.pump();
      expect(view.controller!.page, 7);
    });
  });
}
