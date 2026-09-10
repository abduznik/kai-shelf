import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/download/download_task.dart';

void main() {
  group('DownloadTask.progress', () {
    test('is 0 when there are no pages', () {
      const task = DownloadTask(
        serverId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Manga',
        chapterTitle: 'Chapter 1',
      );
      expect(task.progress, 0);
    });

    test('reflects the fraction of pages marked complete', () {
      const task = DownloadTask(
        serverId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Manga',
        chapterTitle: 'Chapter 1',
        pages: [
          PageDownloadState(
              index: 0, url: 'a', status: DownloadStatus.complete),
          PageDownloadState(
              index: 1, url: 'b', status: DownloadStatus.complete),
          PageDownloadState(
              index: 2, url: 'c', status: DownloadStatus.downloading),
          PageDownloadState(index: 3, url: 'd', status: DownloadStatus.queued),
        ],
      );
      expect(task.progress, 0.5);
    });

    test('is 1 when every page is complete', () {
      const task = DownloadTask(
        serverId: 's1',
        mangaId: 'm1',
        chapterId: 'c1',
        mangaTitle: 'Manga',
        chapterTitle: 'Chapter 1',
        pages: [
          PageDownloadState(
              index: 0, url: 'a', status: DownloadStatus.complete),
        ],
      );
      expect(task.progress, 1);
    });
  });

  group('PageDownloadState.copyWith', () {
    test('preserves unspecified fields and overrides the rest', () {
      const original = PageDownloadState(
          index: 2, url: 'https://example/2.jpg', totalBytes: 1000);
      final updated = original.copyWith(
          status: DownloadStatus.complete, bytesDownloaded: 1000);

      expect(updated.index, 2);
      expect(updated.url, 'https://example/2.jpg');
      expect(updated.totalBytes, 1000);
      expect(updated.status, DownloadStatus.complete);
      expect(updated.bytesDownloaded, 1000);
    });
  });
}
