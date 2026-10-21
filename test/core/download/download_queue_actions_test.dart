import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/download/download_queue.dart';
import 'package:kai_shelf/core/download/download_task.dart';
import 'package:kai_shelf/core/download/downloaded_chapters_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// Records repository traffic without needing a real sqflite database.
class _RecordingRepository implements DownloadedChaptersRepository {
  final List<String> upsertedChapters = [];
  final List<String> deletedChapters = [];

  @override
  Future<void> upsert({
    required String serverId,
    required String mangaId,
    required String chapterId,
    required String localPath,
    required DownloadStatus status,
    int? pageCount,
  }) async {
    upsertedChapters.add(chapterId);
  }

  @override
  Future<DownloadedChapterRecord?> find({
    required String serverId,
    required String chapterId,
  }) async =>
      null;

  @override
  Future<List<DownloadedChapterRecord>> listAll(String serverId) async =>
      const [];

  @override
  Future<void> delete({
    required String serverId,
    required String chapterId,
  }) async {
    deletedChapters.add(chapterId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late ProviderContainer container;
  late DownloadQueue queue;
  late _RecordingRepository repository;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('kai_queue_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempRoot.path);
    container = ProviderContainer();
    addTearDown(container.dispose);
    queue = container.read(downloadQueueProvider.notifier);
    repository = _RecordingRepository();
    queue.attachRepository(repository);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

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

  Directory chapterDir(String chapterId) =>
      Directory(p.join(tempRoot.path, 'downloads', 's1', 'm1', chapterId));

  Future<void> writeChapterFiles(
    String chapterId, {
    int files = 2,
    int bytes = 1024,
  }) async {
    final dir = chapterDir(chapterId);
    await dir.create(recursive: true);
    for (var i = 0; i < files; i++) {
      await File(p.join(dir.path, '$i.jpg'))
          .writeAsBytes(List<int>.filled(bytes, 0));
    }
  }

  Future<void> waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  group('DownloadQueue.cancel', () {
    test('stops an in-flight download and never records it as downloaded',
        () async {
      await writeChapterFiles('c1', files: 1, bytes: 100);

      enqueue('c1');
      expect(
        container.read(downloadQueueProvider).single.status,
        DownloadStatus.downloading,
      );

      queue.cancel(serverId: 's1', chapterId: 'c1');
      expect(container.read(downloadQueueProvider), isEmpty);

      // Give the runner time to finish its attempt against the test HTTP
      // layer: it must not record the cancelled chapter…
      await Future<void>.delayed(const Duration(seconds: 3));

      expect(repository.upsertedChapters, isNot(contains('c1')));
      expect(container.read(downloadQueueProvider), isEmpty);
      // …but it must not wipe the partially downloaded files either.
      expect(await chapterDir('c1').exists(), isTrue);
    });

    test('removes a queued task before it ever starts', () async {
      enqueue('c1');
      enqueue('c2');
      enqueue('c3');

      final statuses = {
        for (final t in container.read(downloadQueueProvider))
          t.chapterId: t.status
      };
      expect(statuses['c1'], DownloadStatus.downloading);
      expect(statuses['c2'], DownloadStatus.downloading);
      expect(statuses['c3'], DownloadStatus.queued);

      queue.cancel(serverId: 's1', chapterId: 'c3');
      expect(
        container.read(downloadQueueProvider).map((t) => t.chapterId),
        ['c1', 'c2'],
      );

      // Once the first two chapters finish, c3 would be picked up if it had
      // survived the cancel.
      await waitUntil(() => repository.upsertedChapters.length >= 2);
      expect(
        container.read(downloadQueueProvider).map((t) => t.chapterId),
        isNot(contains('c3')),
      );
      expect(repository.upsertedChapters, isNot(contains('c3')));
    });
  });

  group('DownloadQueue.retry', () {
    test('re-queues a failed task and drives it through the runner again',
        () async {
      queue.debugSetTasks(
          [task(chapterId: 'c1', status: DownloadStatus.failed)]);

      queue.retry(serverId: 's1', chapterId: 'c1');

      expect(
        container.read(downloadQueueProvider).single.status,
        DownloadStatus.downloading,
      );

      await waitUntil(() => repository.upsertedChapters.isNotEmpty);
      final retried = container.read(downloadQueueProvider).single;
      expect(repository.upsertedChapters, contains('c1'));
      expect(
        retried.status,
        anyOf(DownloadStatus.failed, DownloadStatus.complete),
      );
      expect(
        retried.pages.every((page) => page.status != DownloadStatus.queued),
        isTrue,
      );
    });

    test('ignores tasks that did not fail', () {
      queue.debugSetTasks([task(chapterId: 'c1')]);

      queue.retry(serverId: 's1', chapterId: 'c1');

      final only = container.read(downloadQueueProvider).single;
      expect(only.status, DownloadStatus.complete);
      expect(repository.upsertedChapters, isEmpty);
    });
  });

  group('DownloadQueue.remove', () {
    test('deletes the files, the task and its repository record', () async {
      await writeChapterFiles('c1', files: 3, bytes: 1024);
      queue.debugSetTasks([task(chapterId: 'c1')]);

      await queue.remove(serverId: 's1', mangaId: 'm1', chapterId: 'c1');

      expect(container.read(downloadQueueProvider), isEmpty);
      expect(await chapterDir('c1').exists(), isFalse);
      expect(repository.deletedChapters, contains('c1'));
    });
  });

  group('DownloadQueue.clearFinished', () {
    test('drops finished tasks with their files and keeps the rest', () async {
      await writeChapterFiles('c1', bytes: 1024);
      await writeChapterFiles('c2', bytes: 1024);
      queue.debugSetTasks([
        task(chapterId: 'c1'),
        task(chapterId: 'c2', status: DownloadStatus.failed),
        task(chapterId: 'c3', status: DownloadStatus.downloading),
      ]);

      await queue.clearFinished();

      expect(
        container.read(downloadQueueProvider).map((t) => t.chapterId),
        ['c2', 'c3'],
      );
      expect(await chapterDir('c1').exists(), isFalse);
      expect(await chapterDir('c2').exists(), isTrue);
      expect(repository.deletedChapters, ['c1']);
    });
  });

  group('DownloadQueue.totalStorageBytes', () {
    test('sums on-disk downloads and reflects deletions', () async {
      expect(await queue.totalStorageBytes(), 0);

      await writeChapterFiles('c1', files: 2, bytes: 1024); // 2048
      await writeChapterFiles('c2', files: 3, bytes: 512); // 1536
      expect(await queue.totalStorageBytes(), 3584);

      queue.debugSetTasks([task(chapterId: 'c1')]);
      await queue.remove(serverId: 's1', mangaId: 'm1', chapterId: 'c1');

      expect(await queue.totalStorageBytes(), 1536);
    });
  });
}
