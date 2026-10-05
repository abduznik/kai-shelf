import 'auth_credentials.dart';
import 'models.dart';

/// Common interface every backend adapter (Suwayomi/Komga/Kavita) implements.
/// Feature modules (library/reader/downloads) depend only on this interface
/// and the shared DTOs in models.dart — never on a concrete adapter class.
abstract class ServerBackend {
  BackendType get type;
  ServerConnectionInfo get connectionInfo;

  Future<AuthResult> login(AuthCredentials credentials);
  Future<void> logout();
  Future<bool> validateSession();

  Future<List<KsLibrary>> getLibraries();
  Future<List<KsManga>> getMangaList(
      {String? libraryId, String? searchQuery, int page = 0});

  /// Every manga matching the filters, across all server-side pages.
  /// [getMangaList] returns a single page (Komga's default is only 20 items),
  /// so listing screens must use this to avoid silently truncating libraries.
  Future<List<KsManga>> getAllManga({String? libraryId, String? searchQuery});
  Future<KsManga> getMangaDetail(String mangaId);
  Future<List<KsChapter>> getChapters(String mangaId);
  Future<List<KsPage>> getPages(String chapterId);
  Future<void> updateReadProgress(String chapterId,
      {required bool read, double? lastPageRead});

  /// Resolves a backend-relative path/id into a fully qualified, fetchable
  /// image URL (cover or page), since each backend's auth model determines
  /// what that URL — and any headers it needs — looks like.
  Uri buildImageUrl(String pathOrId);
}

/// Optional capability for backends that have a "source catalog" concept to
/// discover manga not yet in the library (currently: Suwayomi only).
/// Feature code should check `backend is SourceCapableBackend` rather than
/// assuming every backend supports this — Komga/Kavita just index whatever
/// is already on disk, so there is nothing to browse/search server-side.
abstract class SourceCapableBackend {
  Future<List<KsSource>> getSources();
  Future<List<KsSourceManga>> searchSource(String sourceId, String query,
      {int page = 0});

  /// Browses a source's popular/latest listing or searches it, optionally
  /// narrowed by [filters]. Pages are 1-based, like the servers expect.
  Future<KsSourcePage> browseSource(
    String sourceId, {
    SourceBrowseMode mode = SourceBrowseMode.popular,
    String query = '',
    int page = 1,
    List<KsFilterChange> filters = const [],
  });

  /// The filters a source supports, in their default state.
  Future<List<KsSourceFilter>> getSourceFilters(String sourceId);
  Future<void> addToLibrary(String sourceMangaId);
  Future<void> removeFromLibrary(String sourceMangaId);
}

/// Optional capability for backends that can install source extensions
/// from extension repositories (Suwayomi only).
abstract class ExtensionCapableBackend {
  /// Lists known extensions. With [refresh] the server first re-fetches
  /// every repository index.
  Future<List<KsExtension>> getExtensions({bool refresh = false});
  Future<void> installExtension(String pkgName);
  Future<void> updateExtension(String pkgName);
  Future<void> uninstallExtension(String pkgName);
  Future<List<KsExtensionRepo>> getExtensionRepos();
  Future<void> addExtensionRepo(String indexUrl);
  Future<void> removeExtensionRepo(String indexUrl);
}
