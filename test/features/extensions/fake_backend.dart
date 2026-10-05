import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/server_backend.dart';

/// In-memory backend with extension and source support, for widget tests.
class FakeCatalogBackend
    implements ServerBackend, SourceCapableBackend, ExtensionCapableBackend {
  FakeCatalogBackend({List<KsExtension>? extensions, this.pageSize = 3})
      : extensions = extensions ?? [];

  final List<KsExtension> extensions;
  final List<KsExtensionRepo> repos = [];
  final int pageSize;
  final List<String> calls = [];
  final Set<String> library = {};
  List<KsFilterChange>? lastFilters;
  String? lastQuery;
  SourceBrowseMode? lastMode;

  void _replace(String pkg, KsExtension Function(KsExtension) f) {
    final i = extensions.indexWhere((e) => e.pkgName == pkg);
    extensions[i] = f(extensions[i]);
  }

  KsExtension _copy(KsExtension e, {bool? installed, bool? update}) =>
      KsExtension(
        pkgName: e.pkgName,
        name: e.name,
        lang: e.lang,
        versionName: e.versionName,
        isInstalled: installed ?? e.isInstalled,
        hasUpdate: update ?? e.hasUpdate,
        contentWarning: e.contentWarning,
      );

  @override
  Future<List<KsExtension>> getExtensions({bool refresh = false}) async {
    calls.add(refresh ? 'refresh' : 'list');
    return List.of(extensions);
  }

  @override
  Future<void> installExtension(String pkgName) async {
    calls.add('install:$pkgName');
    _replace(pkgName, (e) => _copy(e, installed: true));
  }

  @override
  Future<void> updateExtension(String pkgName) async {
    calls.add('update:$pkgName');
    _replace(pkgName, (e) => _copy(e, update: false));
  }

  @override
  Future<void> uninstallExtension(String pkgName) async {
    calls.add('uninstall:$pkgName');
    _replace(pkgName, (e) => _copy(e, installed: false, update: false));
  }

  @override
  Future<List<KsExtensionRepo>> getExtensionRepos() async => List.of(repos);

  @override
  Future<void> addExtensionRepo(String indexUrl) async {
    calls.add('addRepo:$indexUrl');
    repos.add(KsExtensionRepo(indexUrl: indexUrl, name: 'Repo'));
  }

  @override
  Future<void> removeExtensionRepo(String indexUrl) async {
    calls.add('removeRepo:$indexUrl');
    repos.removeWhere((r) => r.indexUrl == indexUrl);
  }

  @override
  Future<List<KsSource>> getSources() async => const [
        KsSource(id: '1', name: 'Alpha', lang: 'en'),
        KsSource(id: '2', name: 'Beta', lang: 'fr'),
      ];

  @override
  Future<List<KsSourceManga>> searchSource(String sourceId, String query,
          {int page = 0}) async =>
      [];

  @override
  Future<KsSourcePage> browseSource(
    String sourceId, {
    SourceBrowseMode mode = SourceBrowseMode.popular,
    String query = '',
    int page = 1,
    List<KsFilterChange> filters = const [],
  }) async {
    lastMode = mode;
    lastQuery = query;
    lastFilters = filters;
    calls.add('browse:${mode.name}:$page');
    final items = [
      for (var i = 0; i < pageSize; i++)
        KsSourceManga(
          id: 'm${(page - 1) * pageSize + i}',
          title: 'Title ${(page - 1) * pageSize + i}',
          inLibrary: library.contains('m${(page - 1) * pageSize + i}'),
        ),
    ];
    return KsSourcePage(items: items, hasNextPage: page < 2);
  }

  @override
  Future<List<KsSourceFilter>> getSourceFilters(String sourceId) async =>
      const [
        KsSortFilter(name: 'Sort', position: 0, options: ['Popular', 'Title']),
        KsGroupFilter(name: 'Genres', position: 1, children: [
          KsTriStateFilter(name: 'Action', position: 0),
          KsTriStateFilter(name: 'Drama', position: 1),
        ]),
      ];

  @override
  Future<void> addToLibrary(String sourceMangaId) async {
    calls.add('add:$sourceMangaId');
    library.add(sourceMangaId);
  }

  @override
  Future<void> removeFromLibrary(String sourceMangaId) async {
    calls.add('remove:$sourceMangaId');
    library.remove(sourceMangaId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
