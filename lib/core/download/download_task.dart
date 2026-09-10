enum DownloadStatus { queued, downloading, complete, failed, paused }

class PageDownloadState {
  const PageDownloadState({
    required this.index,
    required this.url,
    this.localPath,
    this.status = DownloadStatus.queued,
    this.bytesDownloaded = 0,
    this.totalBytes,
  });

  final int index;
  final String url;
  final String? localPath;
  final DownloadStatus status;
  final int bytesDownloaded;
  final int? totalBytes;

  PageDownloadState copyWith({
    String? localPath,
    DownloadStatus? status,
    int? bytesDownloaded,
    int? totalBytes,
  }) {
    return PageDownloadState(
      index: index,
      url: url,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }
}

class DownloadTask {
  const DownloadTask({
    required this.serverId,
    required this.mangaId,
    required this.chapterId,
    required this.mangaTitle,
    required this.chapterTitle,
    this.status = DownloadStatus.queued,
    this.pages = const [],
  });

  final String serverId;
  final String mangaId;
  final String chapterId;
  final String mangaTitle;
  final String chapterTitle;
  final DownloadStatus status;
  final List<PageDownloadState> pages;

  double get progress {
    if (pages.isEmpty) return 0;
    final completed =
        pages.where((p) => p.status == DownloadStatus.complete).length;
    return completed / pages.length;
  }

  DownloadTask copyWith(
      {DownloadStatus? status, List<PageDownloadState>? pages}) {
    return DownloadTask(
      serverId: serverId,
      mangaId: mangaId,
      chapterId: chapterId,
      mangaTitle: mangaTitle,
      chapterTitle: chapterTitle,
      status: status ?? this.status,
      pages: pages ?? this.pages,
    );
  }
}
