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
