import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Opens (and migrates) the app's local sqlite database. Holds reading
/// progress, the downloaded-chapter index, and cached library metadata —
/// all keyed by serverId so multiple configured servers don't collide.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;
  Database get db => _db;

  static AppDatabase? _instance;

  static Future<AppDatabase> open() async {
    if (_instance != null) return _instance!;
    final directory = await getApplicationSupportDirectory();
    final path = p.join(directory.path, 'kai_shelf.db');

    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE reading_progress (
            server_id TEXT NOT NULL,
            chapter_id TEXT NOT NULL,
            manga_id TEXT NOT NULL,
            read INTEGER NOT NULL DEFAULT 0,
            last_page_read REAL,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (server_id, chapter_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE downloaded_chapters (
            server_id TEXT NOT NULL,
            manga_id TEXT NOT NULL,
            chapter_id TEXT NOT NULL,
            local_path TEXT NOT NULL,
            page_count INTEGER,
            downloaded_at INTEGER,
            status TEXT NOT NULL DEFAULT 'queued',
            PRIMARY KEY (server_id, chapter_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE library_cache (
            server_id TEXT NOT NULL,
            manga_id TEXT NOT NULL,
            json_blob TEXT NOT NULL,
            cached_at INTEGER NOT NULL,
            PRIMARY KEY (server_id, manga_id)
          )
        ''');
      },
    );

    _instance = AppDatabase._(db);
    return _instance!;
  }
}
