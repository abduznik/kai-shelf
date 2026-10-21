import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/download/download_queue.dart';
import 'package:kai_shelf/core/download/download_task.dart';
import 'package:kai_shelf/features/downloads/presentation/downloads_screen.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late ProviderContainer container;
  late DownloadQueue queue;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('kai_dl_screen_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempRoot.path);
    container = ProviderContainer();
    queue = container.read(downloadQueueProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DownloadsScreen()),
    ));
  }

  DownloadTask task({
    required String chapterId,
    DownloadStatus status = DownloadStatus.complete,
    String chapterTitle = 'Chapter 1',
  }) =>
      DownloadTask(
        serverId: 's1',
        mangaId: 'm1',
        chapterId: chapterId,
        mangaTitle: 'Manga',
        chapterTitle: chapterTitle,
        status: status,
        pages: const [
          PageDownloadState(
            index: 0,
            url: 'https://example.invalid/0.jpg',
          ),
        ],
      );

  Directory chapterDir(String chapterId) =>
      Directory(p.join(tempRoot.path, 'downloads', 's1', 'm1', chapterId));

  /// Real dart:io inside a testWidgets body never settles (fake async zone),
  /// so every file operation goes through [WidgetTester.runAsync].
  Future<void> seedFiles(
    WidgetTester tester,
    String chapterId, {
    int files = 2,
    int bytes = 1024,
  }) async {
    await tester.runAsync<void>(() async {
      final dir = chapterDir(chapterId);
      await dir.create(recursive: true);
      for (var i = 0; i < files; i++) {
        await File(p.join(dir.path, '$i.jpg'))
            .writeAsBytes(List<int>.filled(bytes, 0));
      }
    });
  }

  Future<bool> chapterOnDisk(WidgetTester tester, String chapterId) async =>
      await tester.runAsync(() => chapterDir(chapterId).exists()) ?? false;

  void enqueue(String chapterId, {String chapterTitle = 'Chapter 1'}) {
    queue.enqueue(
      serverId: 's1',
      mangaId: 'm1',
      chapterId: chapterId,
      mangaTitle: 'Manga',
      chapterTitle: chapterTitle,
      pages: const [
        KsPage(index: 0, imageUrl: 'https://example.invalid/0.jpg'),
      ],
    );
  }

  /// Drains real file IO (the deletions kicked off by UI actions, plus the
  /// storage re-scans) until the figure reads [expectBytes].
  ///
  /// IO started in the fake test zone delivers events only during a
  /// [WidgetTester.runAsync] window and flushes continuations on the next
  /// pump — i.e. one IO hop per cycle — so we alternate the two until the
  /// post-deletion figure lands, bounded by a wall-clock deadline (the suite
  /// may run in parallel, so a fixed cycle budget would be flaky).
  Future<void> settleStorage(
    WidgetTester tester, {
    required int expectBytes,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    bool done() =>
        container.read(downloadsStorageProvider).valueOrNull == expectBytes;

    final deadline = DateTime.now().add(timeout);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    if (done()) await tester.pump();
  }

  testWidgets('a running task exposes a cancel affordance', (tester) async {
    await pumpScreen(tester);
    enqueue('c1');
    await tester.pump();

    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.byTooltip('Cancel'), findsOneWidget);

    // Cancelling is not destructive, so it must not ask for confirmation.
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();

    expect(find.text('Chapter 1'), findsNothing);
    expect(find.byTooltip('Cancel'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('reports the storage used by downloads', (tester) async {
    await seedFiles(tester, 'c1', files: 2, bytes: 1024);
    queue.debugSetTasks([task(chapterId: 'c1')]);

    await pumpScreen(tester);
    await tester.pump();
    expect(find.text('Storage used'), findsOneWidget);

    await settleStorage(tester, expectBytes: 2048);
    expect(find.text('2.0 KB'), findsOneWidget);
  });

  testWidgets('removing a finished download confirms first, then frees space',
      (tester) async {
    await seedFiles(tester, 'c1', files: 2, bytes: 1024);
    queue.debugSetTasks([task(chapterId: 'c1')]);
    await pumpScreen(tester);
    await settleStorage(tester, expectBytes: 2048);
    expect(find.text('2.0 KB'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Delete download?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);

    // Backing out changes nothing.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(await chapterOnDisk(tester, 'c1'), isTrue);

    // Confirming drops the task, the files and the storage figure.
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Chapter 1'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    await settleStorage(tester, expectBytes: 0);
    expect(await chapterOnDisk(tester, 'c1'), isFalse);
    expect(find.text('0 B'), findsOneWidget);
  });

  testWidgets('clear finished confirms first and keeps unfinished tasks',
      (tester) async {
    await seedFiles(tester, 'c1', files: 2, bytes: 1024); // 2048
    await seedFiles(tester, 'c2', files: 2, bytes: 512); // 1024
    await seedFiles(tester, 'c3', files: 1, bytes: 1024); // 1024
    queue.debugSetTasks([
      task(chapterId: 'c1'),
      task(chapterId: 'c2', chapterTitle: 'Chapter 2'),
      task(
        chapterId: 'c3',
        chapterTitle: 'Chapter 3',
        status: DownloadStatus.failed,
      ),
    ]);
    await pumpScreen(tester);
    await settleStorage(tester, expectBytes: 4096);
    expect(find.text('4.0 KB'), findsOneWidget);
    expect(find.byTooltip('Clear finished'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear finished'));
    await tester.pumpAndSettle();
    expect(find.text('Clear finished downloads?'), findsOneWidget);
    expect(find.textContaining('2 finished downloads'), findsOneWidget);

    // Backing out clears nothing.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Clear finished'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);

    // Confirming removes both finished chapters, keeps the failed one.
    await tester.tap(find.byTooltip('Clear finished'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Chapter 1'), findsNothing);
    expect(find.text('Chapter 2'), findsNothing);
    expect(find.text('Chapter 3'), findsOneWidget);
    expect(find.byTooltip('Clear finished'), findsNothing);

    await settleStorage(tester, expectBytes: 1024);
    expect(await chapterOnDisk(tester, 'c1'), isFalse);
    expect(await chapterOnDisk(tester, 'c2'), isFalse);
    expect(await chapterOnDisk(tester, 'c3'), isTrue);
    expect(find.text('1.0 KB'), findsOneWidget);
  });

  testWidgets('a failed task offers a retry that re-queues it', (tester) async {
    queue.debugSetTasks([
      task(chapterId: 'c1', status: DownloadStatus.failed),
    ]);
    await pumpScreen(tester);
    await tester.pump();

    expect(find.byTooltip('Retry'), findsOneWidget);

    await tester.tap(find.byTooltip('Retry'));
    await tester.pump();

    expect(
      container.read(downloadQueueProvider).single.status,
      DownloadStatus.downloading,
    );
    expect(find.byTooltip('Retry'), findsNothing);
    expect(find.byTooltip('Cancel'), findsOneWidget);
  });

  testWidgets('shows an empty state when nothing is downloaded',
      (tester) async {
    await pumpScreen(tester);
    await tester.pump();

    expect(find.text('No downloads yet.'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.text('Storage used'), findsOneWidget);
    expect(find.byTooltip('Clear finished'), findsNothing);
    expect(find.byTooltip('Remove'), findsNothing);
  });
}
