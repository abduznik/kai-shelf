import '../backend/models.dart';
import '../backend/server_backend.dart';
import 'chapter_check_engine.dart';

/// Feeds the engine from whatever [ServerBackend] is active. Deliberately
/// dumb: it exists so the engine never learns about adapters, tokens or
/// pagination, and so tests never see a real HTTP client.
class BackendChapterCatalog implements ChapterCatalog {
  const BackendChapterCatalog(this.backend);

  final ServerBackend backend;

  /// The whole library is the "followed" set — every self-hosted reader
  /// treats library membership that way, and the engine's silent baseline
  /// keeps a first check from announcing back-catalogue chapters.
  @override
  Future<List<KsManga>> trackedManga() => backend.getAllManga();

  @override
  Future<List<KsChapter>> chaptersFor(String mangaId) =>
      backend.getChapters(mangaId);
}
