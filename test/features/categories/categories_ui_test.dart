import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/providers/backend_providers.dart';
import 'package:kai_shelf/features/categories/presentation/category_manage_screen.dart';
import 'package:kai_shelf/features/library/presentation/manga_detail_screen.dart';
import 'package:kai_shelf/features/library/presentation/source_search_screen.dart';

import 'fake_category_backend.dart';

Widget _app(FakeCategoryBackend backend, Widget home) => ProviderScope(
      overrides: [activeBackendProvider.overrideWithValue(backend)],
      child: MaterialApp(home: home),
    );

void main() {
  group('manga detail', () {
    testWidgets('heart opens the picker and saves several categories',
        (tester) async {
      final b = FakeCategoryBackend();
      await tester.pumpWidget(_app(b, const MangaDetailScreen(mangaId: 'm1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit categories'));
      await tester.pumpAndSettle();

      // The built-in default category is not something to tick.
      expect(find.text('Default'), findsNothing);
      await tester.tap(find.text('Reading'));
      await tester.tap(find.text('Plan to read'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(b.calls, contains('set:m1:1,2'));
      expect(b.membership['m1'], {'1', '2'});
    });

    testWidgets('a new category can be created inline and is pre-ticked',
        (tester) async {
      final b = FakeCategoryBackend();
      await tester.pumpWidget(_app(b, const MangaDetailScreen(mangaId: 'm1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New category'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Finished');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Finished'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(b.calls, contains('create:Finished:-'));
      expect(b.membership['m1'], {'10'});
    });

    testWidgets('a server that refuses empty categories gets the manga id',
        (tester) async {
      final b = FakeCategoryBackend(emptyCategoriesAllowed: false);
      await tester.pumpWidget(_app(b, const MangaDetailScreen(mangaId: 'm1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New category'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Faves');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(b.calls, contains('create:Faves:m1'));
    });

    testWidgets('the sheet can still remove the manga from the library',
        (tester) async {
      final b = FakeCategoryBackend();
      await tester.pumpWidget(_app(b, const MangaDetailScreen(mangaId: 'm1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from library'));
      await tester.pumpAndSettle();

      expect(b.calls, contains('remove:m1'));
    });

    testWidgets('adding a preview with no pick lands in the library only',
        (tester) async {
      final b = FakeCategoryBackend()..library.clear();
      await tester.pumpWidget(_app(b, const MangaDetailScreen(mangaId: 'm9')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add to library').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add to library'));
      await tester.pumpAndSettle();

      expect(b.calls, ['add:m9', 'set:m9:']);
    });

    testWidgets('bookmarks toggle per chapter and filter the list',
        (tester) async {
      final b = FakeCategoryBackend();
      await tester.pumpWidget(_app(b, const MangaDetailScreen(mangaId: 'm1')));
      await tester.pumpAndSettle();

      expect(find.text('Chapter 1'), findsOneWidget);
      expect(find.text('Chapter 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Show bookmarked chapters only'));
      await tester.pumpAndSettle();
      expect(find.text('Chapter 1'), findsNothing);
      expect(find.text('Chapter 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove bookmark'));
      await tester.pumpAndSettle();
      expect(b.calls, contains('bookmark:c2:false'));
      expect(find.text('No bookmarked chapters.'), findsOneWidget);

      await tester.tap(find.byTooltip('Show all chapters'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bookmark chapter').first);
      await tester.pumpAndSettle();
      expect(b.calls, contains('bookmark:c3:true'));
    });
  });

  group('source search', () {
    testWidgets('heart on a result offers the category picker', (tester) async {
      final b = FakeCategoryBackend()..library.clear();
      await tester.pumpWidget(_app(
          b, const SourceSearchScreen(sourceId: '1', sourceName: 'Alpha')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add to library').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reading'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add to library'));
      await tester.pumpAndSettle();

      expect(b.calls, ['add:s0', 'set:s0:1']);
      expect(find.byTooltip('Remove from library'), findsOneWidget);
    });
  });

  group('manage screen', () {
    testWidgets('lists categories with Default separate and read-only',
        (tester) async {
      final b = FakeCategoryBackend();
      await tester.pumpWidget(_app(b, const CategoryManageScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Plan to read'), findsOneWidget);
      // Only the two editable rows have a menu.
      expect(find.byType(PopupMenuButton<String>), findsNWidgets(2));
    });

    testWidgets('creates, renames and deletes', (tester) async {
      final b = FakeCategoryBackend();
      await tester.pumpWidget(_app(b, const CategoryManageScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New category'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Finished');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Finished'), findsOneWidget);

      await tester.tap(find.byTooltip('Options for Reading'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Now reading');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Now reading'), findsOneWidget);
      expect(find.text('Reading'), findsNothing);

      await tester.tap(find.byTooltip('Options for Plan to read'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Plan to read'), findsNothing);
      expect(
          b.calls, ['create:Finished:-', 'rename:1:Now reading', 'delete:2']);
    });

    testWidgets('dragging the handle moves a category', (tester) async {
      final b = FakeCategoryBackend();
      await tester.pumpWidget(_app(b, const CategoryManageScreen()));
      await tester.pumpAndSettle();

      // Move "Plan to read" (second editable row) above "Reading".
      final gesture = await tester
          .startGesture(tester.getCenter(find.byIcon(Icons.drag_handle).last));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -12));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(b.calls, ['move:2:0']);
      final reading = tester.getTopLeft(find.text('Reading')).dy;
      final plan = tester.getTopLeft(find.text('Plan to read')).dy;
      expect(plan, lessThan(reading));
    });

    testWidgets('hides New for servers that cannot hold empty categories',
        (tester) async {
      final b = FakeCategoryBackend(emptyCategoriesAllowed: false);
      await tester.pumpWidget(_app(b, const CategoryManageScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.text('Reading'), findsOneWidget);
    });
  });
}
