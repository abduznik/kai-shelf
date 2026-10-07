import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/server_backend.dart';

/// In-memory backend with Suwayomi-like categories and chapter bookmarks,
/// for widget tests. [emptyCategoriesAllowed] false mimics Komga.
class FakeCategoryBackend
    implements
        ServerBackend,
        SourceCapableBackend,
        CategoryCapableBackend,
        ChapterBookmarkCapableBackend {
  FakeCategoryBackend({this.emptyCategoriesAllowed = true}) {
    categories = [
      const KsCategory(id: '0', name: 'Default', isDefault: true),
      const KsCategory(id: '1', name: 'Reading'),
      const KsCategory(id: '2', name: 'Plan to read'),
    ];
  }

  final bool emptyCategoriesAllowed;
  late List<KsCategory> categories;
  final Map<String, Set<String>> membership = {};
  final Set<String> library = {'m1'};
  final Set<String> bookmarked = {'c2'};
  final List<String> calls = [];
  var _nextId = 10;

  @override
  String get categoryNoun => 'category';

  @override
  bool get canReorderCategories => emptyCategoriesAllowed;

  @override
  bool get canCreateEmptyCategory => emptyCategoriesAllowed;

  @override
  Future<List<KsCategory>> getCategories() async => List.of(categories);

  @override
  Future<KsCategory> createCategory(String name, {String? firstMangaId}) async {
    calls.add('create:$name:${firstMangaId ?? '-'}');
    final c = KsCategory(id: '${_nextId++}', name: name);
    categories.add(c);
    if (firstMangaId != null) {
      membership.putIfAbsent(firstMangaId, () => {}).add(c.id);
    }
    return c;
  }

  @override
  Future<void> renameCategory(String categoryId, String name) async {
    calls.add('rename:$categoryId:$name');
    categories = [
      for (final c in categories)
        c.id == categoryId
            ? KsCategory(id: c.id, name: name, mangaCount: c.mangaCount)
            : c
    ];
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    calls.add('delete:$categoryId');
    categories.removeWhere((c) => c.id == categoryId);
  }

  @override
  Future<void> moveCategory(String categoryId, int newIndex) async {
    calls.add('move:$categoryId:$newIndex');
    final editable = categories.where((c) => !c.isDefault).toList();
    final item = editable.firstWhere((c) => c.id == categoryId);
    editable
      ..remove(item)
      ..insert(newIndex, item);
    categories = [...categories.where((c) => c.isDefault), ...editable];
  }

  @override
  Future<Set<String>> getMangaCategoryIds(String mangaId) async =>
      Set.of(membership[mangaId] ?? {});

  @override
  Future<void> setMangaCategories(
      String mangaId, Set<String> categoryIds) async {
    calls.add('set:$mangaId:${(categoryIds.toList()..sort()).join(',')}');
    membership[mangaId] = Set.of(categoryIds);
  }

  @override
  Future<List<KsManga>> getCategoryManga(String categoryId) async => [
        for (final e in membership.entries)
          if (e.value.contains(categoryId))
            KsManga(id: e.key, title: 'Manga ${e.key}'),
      ];

  @override
  Future<void> setChapterBookmarked(String chapterId, bool value) async {
    calls.add('bookmark:$chapterId:$value');
    value ? bookmarked.add(chapterId) : bookmarked.remove(chapterId);
  }

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
  Future<KsManga> getMangaDetail(String mangaId) async => KsManga(
        id: mangaId,
        title: 'Manga $mangaId',
        inLibrary: library.contains(mangaId),
      );

  @override
  Future<List<KsChapter>> getChapters(String mangaId) async => [
        for (var i = 1; i <= 3; i++)
          KsChapter(
            id: 'c$i',
            mangaId: mangaId,
            title: 'Chapter $i',
            chapterNumber: i.toDouble(),
            bookmarked: bookmarked.contains('c$i'),
          ),
      ];

  @override
  Future<KsSourcePage> browseSource(
    String sourceId, {
    SourceBrowseMode mode = SourceBrowseMode.popular,
    String query = '',
    int page = 1,
    List<KsFilterChange> filters = const [],
  }) async =>
      KsSourcePage(items: [
        for (var i = 0; i < 3; i++)
          KsSourceManga(
              id: 's$i', title: 'Source $i', inLibrary: library.contains('s$i'))
      ], hasNextPage: false);

  @override
  Future<List<KsSourceFilter>> getSourceFilters(String sourceId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
