import '../auth_credentials.dart';
import '../models.dart';
import '../server_backend.dart';

/// Komga adapter — REST API, HTTP Basic Auth or X-API-Key.
/// Full implementation lands in milestone M5; this stub exists now only so
/// [BackendType.komga] is a valid, compiling branch of the active-backend
/// switch while M1 wires the rest of the app around the interface.
class KomgaBackend implements ServerBackend {
  KomgaBackend(this.connectionInfo);

  @override
  final ServerConnectionInfo connectionInfo;

  @override
  BackendType get type => BackendType.komga;

  @override
  Future<AuthResult> login(AuthCredentials credentials) async {
    return const AuthResult.failure(
        'Komga support is not implemented yet (see milestone M5)');
  }

  @override
  Future<void> logout() async {}

  @override
  Future<bool> validateSession() async => false;

  @override
  Future<List<KsLibrary>> getLibraries() => _unimplemented();

  @override
  Future<List<KsManga>> getMangaList(
          {String? libraryId, String? searchQuery, int page = 0}) =>
      _unimplemented();

  @override
  Future<KsManga> getMangaDetail(String mangaId) => _unimplemented();

  @override
  Future<List<KsChapter>> getChapters(String mangaId) => _unimplemented();

  @override
  Future<List<KsPage>> getPages(String chapterId) => _unimplemented();

  @override
  Future<void> updateReadProgress(String chapterId,
          {required bool read, double? lastPageRead}) =>
      _unimplemented();

  @override
  Uri buildImageUrl(String pathOrId) =>
      connectionInfo.baseUrl.replace(path: pathOrId);

  Future<Never> _unimplemented() => Future.error(UnimplementedError(
      'Komga support is not implemented yet (see milestone M5)'));
}
