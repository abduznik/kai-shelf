import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/download/download_queue.dart';
import 'package:kai_shelf/core/download/download_task.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '.test_support';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  group('DownloadQueue.enqueue', () {
    test('adds a new task for a chapter not already queued', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(downloadQueueProvider.notifier).enqueue(
        serverId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Manga',
        chapterTitle: 'Chapter 1',
        pages: const [
          KsPage(index: 0, imageUrl: 'https://example.invalid/0.jpg')
        ],
      );

      final tasks = container.read(downloadQueueProvider);
      expect(tasks, hasLength(1));
      expect(tasks.first.chapterId, 'c1');
      expect(tasks.first.pages, hasLength(1));
    });

    test('does not duplicate a chapter already queued or in progress', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(downloadQueueProvider.notifier);
      for (var i = 0; i < 2; i++) {
        notifier.enqueue(
          serverId: 's1',
          mangaId: 'm1',
          chapterId: 'c1',
          mangaTitle: 'Manga',
          chapterTitle: 'Chapter 1',
          pages: const [
            KsPage(index: 0, imageUrl: 'https://example.invalid/0.jpg')
          ],
        );
      }

      final tasks = container.read(downloadQueueProvider);
      expect(tasks, hasLength(1));
    });

    test('allows separate chapters of the same manga to queue independently',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(downloadQueueProvider.notifier);
      notifier.enqueue(
        serverId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Manga',
        chapterTitle: 'Chapter 1',
        pages: const [
          KsPage(index: 0, imageUrl: 'https://example.invalid/0.jpg')
        ],
      );
      notifier.enqueue(
        serverId: 's1',
        mangaId: 'm1',
        chapterId: 'c2',
        mangaTitle: 'Manga',
        chapterTitle: 'Chapter 2',
        pages: const [
          KsPage(index: 0, imageUrl: 'https://example.invalid/0.jpg')
        ],
      );

      final tasks = container.read(downloadQueueProvider);
      expect(tasks, hasLength(2));
      expect(tasks.map((t) => t.chapterId), containsAll(['c1', 'c2']));
    });
  });

  test(
      'a page download that fails marks the task failed, not stuck downloading',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(downloadQueueProvider.notifier).enqueue(
      serverId: 's1',
      mangaId: 'm1',
      chapterId: 'c1',
      mangaTitle: 'Manga',
      chapterTitle: 'Chapter 1',
      pages: const [
        KsPage(index: 0, imageUrl: 'https://example.invalid/0.jpg')
      ],
    );

    // The real DownloadWorker will fail against this unreachable host;
    // wait for that failure to propagate through the queue's state.
    await Future<void>.delayed(const Duration(seconds: 2));

    final task = container.read(downloadQueueProvider).first;
    expect(task.status, DownloadStatus.failed);
  });
}
