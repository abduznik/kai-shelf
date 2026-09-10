import 'package:sqflite/sqflite.dart';

import '../storage/app_database.dart';
import 'download_task.dart';

class DownloadedChapterRecord {
  const DownloadedChapterRecord({
    required this.serverId,
    required this.mangaId,
    required this.chapterId,
    required this.localPath,
    required this.status,
    this.pageCount,
  });

  final String serverId;
  final String mangaId;
  final String chapterId;
  final String localPath;
  final DownloadStatus status;
  final int? pageCount;
}

class DownloadedChaptersRepository {
  DownloadedChaptersRepository(this._database);

  final AppDatabase _database;

  Future<void> upsert({
    required String serverId,
    required String mangaId,
    required String chapterId,
    required String localPath,
    required DownloadStatus status,
    int? pageCount,
  }) async {
    await _database.db.insert(
        'downloaded_chapters',
        {
          'server_id': serverId,
          'manga_id': mangaId,
          'chapter_id': chapterId,
          'local_path': localPath,
          'page_count': pageCount,
          'downloaded_at': DateTime.now().millisecondsSinceEpoch,
          'status': status.name,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<DownloadedChapterRecord?> find({
    required String serverId,
    required String chapterId,
  }) async {
    final rows = await _database.db.query(
      'downloaded_chapters',
      where: 'server_id = ? AND chapter_id = ?',
      whereArgs: [serverId, chapterId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return DownloadedChapterRecord(
      serverId: row['server_id'] as String,
      mangaId: row['manga_id'] as String,
      chapterId: row['chapter_id'] as String,
      localPath: row['local_path'] as String,
      status: DownloadStatus.values.byName(row['status'] as String),
      pageCount: row['page_count'] as int?,
    );
  }

  Future<List<DownloadedChapterRecord>> listAll(String serverId) async {
    final rows = await _database.db.query(
      'downloaded_chapters',
      where: 'server_id = ?',
      whereArgs: [serverId],
    );
    return rows
        .map(
          (row) => DownloadedChapterRecord(
            serverId: row['server_id'] as String,
            mangaId: row['manga_id'] as String,
            chapterId: row['chapter_id'] as String,
            localPath: row['local_path'] as String,
            status: DownloadStatus.values.byName(row['status'] as String),
            pageCount: row['page_count'] as int?,
          ),
        )
        .toList();
  }

  Future<void> delete(
      {required String serverId, required String chapterId}) async {
    await _database.db.delete(
      'downloaded_chapters',
      where: 'server_id = ? AND chapter_id = ?',
      whereArgs: [serverId, chapterId],
    );
  }
}
