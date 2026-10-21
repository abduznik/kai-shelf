import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Downloads a single page to disk, resuming a partial file via a Range
/// request when the server honors it (Suwayomi/Komga/Kavita's static
/// image serving generally does).
class DownloadWorker {
  DownloadWorker({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> chapterDirectoryPath({
    required String serverId,
    required String mangaId,
    required String chapterId,
  }) async {
    final baseDir = await getApplicationSupportDirectory();
    return p.join(baseDir.path, 'downloads', serverId, mangaId, chapterId);
  }

  /// Root folder holding every downloaded chapter, across sessions.
  Future<String> downloadsRootPath() async {
    final baseDir = await getApplicationSupportDirectory();
    return p.join(baseDir.path, 'downloads');
  }

  /// Deletes a chapter's directory and every file inside it.
  Future<void> deleteChapterDirectory({
    required String serverId,
    required String mangaId,
    required String chapterId,
  }) async {
    final dir = Directory(await chapterDirectoryPath(
      serverId: serverId,
      mangaId: mangaId,
      chapterId: chapterId,
    ));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Sum of the sizes of every file stored under the downloads root.
  ///
  /// Tolerates files vanishing mid-scan (a deletion racing this walk): they
  /// simply do not count, instead of failing the whole figure.
  Future<int> downloadsStorageBytes() async {
    try {
      final root = Directory(await downloadsRootPath());
      if (!await root.exists()) return 0;
      var total = 0;
      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        try {
          total += await entity.length();
        } catch (_) {
          // Deleted while scanning — it no longer occupies storage.
        }
      }
      return total;
    } catch (_) {
      // Downloads root unreadable or removed: nothing to account for.
      return 0;
    }
  }

  Future<String> downloadPage({
    required String url,
    required Map<String, String>? headers,
    required String localPath,
  }) async {
    final file = File(localPath);
    await file.parent.create(recursive: true);

    final existingBytes = await file.exists() ? await file.length() : 0;
    final requestHeaders = {...(headers ?? {})};
    if (existingBytes > 0) {
      requestHeaders['Range'] = 'bytes=$existingBytes-';
    }

    final request = http.Request('GET', Uri.parse(url));
    request.headers.addAll(requestHeaders);
    final response = await _client.send(request);

    if (response.statusCode == 200 || response.statusCode == 206) {
      final sink = file.openWrite(
        mode: response.statusCode == 206 ? FileMode.append : FileMode.write,
      );
      await response.stream.pipe(sink);
      await sink.close();
      return localPath;
    }

    throw Exception(
        'Download failed with status ${response.statusCode} for $url');
  }

  void dispose() => _client.close();
}
