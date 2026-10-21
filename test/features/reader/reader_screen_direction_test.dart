import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/download/offline_page_resolver.dart';
import 'package:kai_shelf/core/providers/library_providers.dart';
import 'package:kai_shelf/core/providers/reader_prefs_provider.dart';
import 'package:kai_shelf/features/reader/presentation/paged_reader_view.dart';
import 'package:kai_shelf/features/reader/presentation/reader_screen.dart';
import 'package:kai_shelf/features/reader/presentation/widgets/reader_controls_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _overlay({
  ReaderMode mode = ReaderMode.paged,
  ReadingDirection direction = ReadingDirection.ltr,
  ValueChanged<ReadingDirection>? onDirectionChanged,
  bool hasOverride = false,
  VoidCallback? onResetToDefault,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ReaderControlsOverlay(
          visible: true,
          currentPage: 0,
          totalPages: 10,
          mode: mode,
          onModeChanged: (_) {},
          onClose: () {},
          direction: direction,
          onDirectionChanged: onDirectionChanged,
          hasOverride: hasOverride,
          onResetToDefault: onResetToDefault,
        ),
      ),
    );

// Local pages with missing files render the error icon, so no network or
// image plugins are involved.
List<KsPage> _pages(int n) => [
      for (var i = 0; i < n; i++)
        KsPage(index: i, imageUrl: '', localPath: '/nonexistent/$i.jpg'),
    ];

void main() {
  group('direction control', () {
    testWidgets('switches the reading direction to RTL and back',
        (tester) async {
      final chosen = <ReadingDirection>[];
      await tester.pumpWidget(_overlay(onDirectionChanged: chosen.add));

      await tester.tap(find.byTooltip('Read right to left'));
      expect(chosen, [ReadingDirection.rtl]);

      await tester.pumpWidget(_overlay(
        direction: ReadingDirection.rtl,
        onDirectionChanged: chosen.add,
      ));
      await tester.tap(find.byTooltip('Read left to right'));
      expect(chosen, [ReadingDirection.rtl, ReadingDirection.ltr]);
    });

    testWidgets('is disabled when nothing is wired to it', (tester) async {
      await tester.pumpWidget(_overlay());
      final button = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.format_textdirection_l_to_r));
      expect(button.onPressed, isNull);
    });
  });

  group('reset-to-default control', () {
    testWidgets('is disabled while the title follows the global default',
        (tester) async {
      await tester.pumpWidget(_overlay(onResetToDefault: () {}));
      final button = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.settings_backup_restore));
      expect(button.onPressed, isNull);
    });

    testWidgets('fires when the title has an override', (tester) async {
      var reset = 0;
      await tester.pumpWidget(
          _overlay(hasOverride: true, onResetToDefault: () => reset++));
      await tester.tap(find.byTooltip('Reset to default'));
      expect(reset, 1);
    });
  });

  group('PagedReaderView', () {
    testWidgets('rightToLeft reverses the page view', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PagedReaderView(
          pages: _pages(6),
          rightToLeft: true,
          onPageChanged: (_) {},
        ),
      ));
      await tester.pump();
      final view = tester.widget<PageView>(find.byType(PageView));
      expect(view.reverse, isTrue);
    });

    testWidgets('defaults to left-to-right', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PagedReaderView(pages: _pages(6), onPageChanged: (_) {}),
      ));
      await tester.pump();
      final view = tester.widget<PageView>(find.byType(PageView));
      expect(view.reverse, isFalse);
    });
  });

  group('ReaderScreen wiring', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('reads the per-title RTL override into the paged view',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          offlinePagesProvider
              .overrideWith((ref, chapterId) async => _pages(6)),
          chaptersProvider.overrideWith((ref, mangaId) async => const [
                KsChapter(
                  id: 'chapter-1',
                  mangaId: 'manga-1',
                  title: 'Chapter 1',
                  chapterNumber: 1,
                ),
              ]),
        ],
      );
      addTearDown(container.dispose);

      final overrides = container.read(readerTitleOverridesProvider.notifier);
      await overrides.ready;
      await overrides.setDirection('manga-1', ReadingDirection.rtl);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ReaderScreen(mangaId: 'manga-1', chapterId: 'chapter-1'),
        ),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final view = tester.widget<PageView>(find.byType(PageView));
      expect(view.reverse, isTrue,
          reason: 'the per-title RTL override must reach PagedReaderView');
    });

    testWidgets('leaves titles without an override left-to-right',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          offlinePagesProvider
              .overrideWith((ref, chapterId) async => _pages(6)),
          chaptersProvider.overrideWith((ref, mangaId) async => const [
                KsChapter(
                  id: 'chapter-1',
                  mangaId: 'manga-1',
                  title: 'Chapter 1',
                  chapterNumber: 1,
                ),
              ]),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ReaderScreen(mangaId: 'manga-1', chapterId: 'chapter-1'),
        ),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final view = tester.widget<PageView>(find.byType(PageView));
      expect(view.reverse, isFalse);
    });
  });
}
