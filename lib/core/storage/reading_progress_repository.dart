import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class ReadingProgress {
  const ReadingProgress(
      {required this.chapterId, required this.read, this.lastPageRead});

  final String chapterId;
  final bool read;
  final double? lastPageRead;
}

class ReadingProgressRepository {
  ReadingProgressRepository(this._database);

  final AppDatabase _database;

  Future<void> save({
    required String serverId,
    required String mangaId,
    required String chapterId,
    required bool read,
    double? lastPageRead,
  }) async {
    await _database.db.insert(
        'reading_progress',
        {
          'server_id': serverId,
          'manga_id': mangaId,
          'chapter_id': chapterId,
          'read': read ? 1 : 0,
          'last_page_read': lastPageRead,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<ReadingProgress?> get(
      {required String serverId, required String chapterId}) async {
    final rows = await _database.db.query(
      'reading_progress',
      where: 'server_id = ? AND chapter_id = ?',
      whereArgs: [serverId, chapterId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return ReadingProgress(
      chapterId: row['chapter_id'] as String,
      read: (row['read'] as int) == 1,
      lastPageRead: row['last_page_read'] as double?,
    );
  }
}
