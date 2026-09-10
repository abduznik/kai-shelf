import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../backend/models.dart';
import '../providers/backend_providers.dart';
import '../providers/library_providers.dart';
import '../providers/storage_providers.dart';
import 'download_task.dart';

/// Resolves a chapter's pages preferring locally downloaded files over the
/// network URL, so a downloaded chapter can be read fully offline.
final offlinePagesProvider =
    FutureProvider.autoDispose.family<List<KsPage>, String>((
  ref,
  chapterId,
) async {
  final connection = ref.watch(activeConnectionProvider);
  final repository = ref.watch(downloadedChaptersRepositoryProvider);

  if (connection != null && repository != null) {
    final record = await repository.find(
        serverId: connection.serverId, chapterId: chapterId);
    if (record != null && record.status == DownloadStatus.complete) {
      final pageCount = record.pageCount ?? 0;
      final localPages = <KsPage>[];
      for (var i = 0; i < pageCount; i++) {
        final localPath = p.join(record.localPath, '$i.jpg');
        if (await File(localPath).exists()) {
          localPages.add(KsPage(index: i, imageUrl: '', localPath: localPath));
        }
      }
      if (localPages.length == pageCount && pageCount > 0) {
        return localPages;
      }
    }
  }

  return ref.watch(pagesProvider(chapterId).future);
});
