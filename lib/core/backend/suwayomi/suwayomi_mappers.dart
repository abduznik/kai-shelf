import '../models.dart';

/// Translates Suwayomi's GraphQL response shapes into the shared DTOs.
class SuwayomiMappers {
  static MangaStatus mapStatus(String? raw) {
    switch (raw) {
      case 'ONGOING':
        return MangaStatus.ongoing;
      case 'COMPLETED':
        return MangaStatus.completed;
      case 'LICENSED':
        return MangaStatus.licensed;
      case 'PUBLISHING_FINISHED':
        return MangaStatus.publishingFinished;
      case 'CANCELLED':
        return MangaStatus.cancelled;
      case 'ON_HIATUS':
        return MangaStatus.onHiatus;
      default:
        return MangaStatus.unknown;
    }
  }

  static KsLibrary libraryFromJson(Map<String, dynamic> json) {
    return KsLibrary(
      id: json['id'].toString(),
      name: json['name'] as String,
      mangaCount: (json['mangas']?['totalCount'] as int?) ?? 0,
    );
  }

  static KsManga mangaFromJson(
    Map<String, dynamic> json, {
    Uri Function(String path)? buildImageUrl,
    Map<String, String>? coverHeaders,
  }) {
    final thumbnailPath = json['thumbnailUrl'] as String?;
    return KsManga(
      id: json['id'].toString(),
      title: json['title'] as String,
      coverUrl: thumbnailPath == null
          ? null
          : (buildImageUrl?.call(thumbnailPath) ?? Uri.parse(thumbnailPath))
              .toString(),
      coverHeaders: coverHeaders,
      description: json['description'] as String?,
      genres: (json['genre'] as List?)?.map((g) => g.toString()).toList() ??
          const [],
      status: mapStatus(json['status'] as String?),
      lastUpdated: json['lastFetchedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              int.parse(json['lastFetchedAt'].toString()))
          : null,
      inLibrary: json['inLibrary'] as bool? ?? true,
      backendExtra: json,
    );
  }

  static KsSource sourceFromJson(Map<String, dynamic> json) {
    return KsSource(
      id: json['id'].toString(),
      name: json['name'] as String,
      lang: json['lang'] as String?,
      iconUrl: json['iconUrl'] as String?,
      displayName: json['displayName'] as String?,
      supportsLatest: json['supportsLatest'] as bool? ?? true,
      contentWarning: mapContentWarning(json['contentWarning'] as String?),
    );
  }

  static ContentWarning mapContentWarning(String? raw) {
    switch (raw) {
      case 'SAFE':
        return ContentWarning.safe;
      case 'MIXED':
        return ContentWarning.mixed;
      case 'NSFW':
        return ContentWarning.nsfw;
      default:
        return ContentWarning.unknown;
    }
  }

  static KsExtension extensionFromJson(Map<String, dynamic> json,
      {Uri Function(String path)? buildImageUrl}) {
    final icon = json['iconUrl'] as String?;
    return KsExtension(
      pkgName: json['pkgName'] as String,
      name: json['name'] as String,
      lang: json['lang'] as String?,
      versionName: json['versionName'] as String?,
      iconUrl: icon == null
          ? null
          : (buildImageUrl?.call(icon) ?? Uri.parse(icon)).toString(),
      isInstalled: json['isInstalled'] as bool? ?? false,
      hasUpdate: json['hasUpdate'] as bool? ?? false,
      isObsolete: json['isObsolete'] as bool? ?? false,
      contentWarning: mapContentWarning(json['contentWarning'] as String?),
      storeName: json['extensionStore']?['name'] as String?,
    );
  }

  static KsExtensionRepo repoFromJson(Map<String, dynamic> json) {
    return KsExtensionRepo(
      indexUrl: json['indexUrl'] as String,
      name: json['name'] as String? ?? json['indexUrl'] as String,
    );
  }

  static KsTriState mapTriState(String? raw) {
    switch (raw) {
      case 'INCLUDE':
        return KsTriState.include;
      case 'EXCLUDE':
        return KsTriState.exclude;
      default:
        return KsTriState.ignore;
    }
  }

  static String triStateToJson(KsTriState state) {
    switch (state) {
      case KsTriState.include:
        return 'INCLUDE';
      case KsTriState.exclude:
        return 'EXCLUDE';
      case KsTriState.ignore:
        return 'IGNORE';
    }
  }

  /// Maps the aliased filter union (see SuwayomiQueries._filterLeaf).
  /// Returns null for unknown filter kinds so a new server version can't
  /// break the whole filter sheet.
  static KsSourceFilter? filterFromJson(Map<String, dynamic> json, int pos) {
    switch (json['__typename']) {
      case 'HeaderFilter':
        return KsHeaderFilter(name: json['hName'] as String, position: pos);
      case 'SeparatorFilter':
        return KsSeparatorFilter(
            name: json['sName'] as String? ?? '', position: pos);
      case 'TextFilter':
        return KsTextFilter(
            name: json['tName'] as String,
            position: pos,
            value: json['textDefault'] as String? ?? '');
      case 'CheckBoxFilter':
        return KsCheckBoxFilter(
            name: json['cName'] as String,
            position: pos,
            value: json['checkDefault'] as bool? ?? false);
      case 'TriStateFilter':
        return KsTriStateFilter(
            name: json['triName'] as String,
            position: pos,
            value: mapTriState(json['triDefault'] as String?));
      case 'SelectFilter':
        return KsSelectFilter(
            name: json['selName'] as String,
            position: pos,
            options: (json['selValues'] as List).map((v) => '$v').toList(),
            selected: json['selDefault'] as int? ?? 0);
      case 'SortFilter':
        final def = json['sortDefault'] as Map<String, dynamic>?;
        return KsSortFilter(
            name: json['sortName'] as String,
            position: pos,
            options: (json['sortValues'] as List).map((v) => '$v').toList(),
            selected: def?['index'] as int? ?? 0,
            ascending: def?['ascending'] as bool? ?? false);
      case 'GroupFilter':
        return KsGroupFilter(
            name: json['gName'] as String,
            position: pos,
            children: filtersFromJson(json['groupFilters'] as List? ?? []));
    }
    return null;
  }

  /// Positions are assigned from the index in the raw list (including
  /// skipped unknown kinds), since that is how servers address filters.
  static List<KsSourceFilter> filtersFromJson(List raw) {
    final result = <KsSourceFilter>[];
    for (var i = 0; i < raw.length; i++) {
      final f = filterFromJson(raw[i] as Map<String, dynamic>, i);
      if (f != null) result.add(f);
    }
    return result;
  }

  /// Encodes a change as the nested `FilterChangeInput` the server wants:
  /// every path step but the last is wrapped in a `groupChange`.
  static Map<String, dynamic> filterChangeToJson(KsFilterChange change) {
    final leaf = <String, dynamic>{'position': change.path.last};
    if (change.checkBox != null) leaf['checkBoxState'] = change.checkBox;
    if (change.triState != null) {
      leaf['triState'] = triStateToJson(change.triState!);
    }
    if (change.select != null) leaf['selectState'] = change.select;
    if (change.text != null) leaf['textState'] = change.text;
    if (change.sortIndex != null) {
      leaf['sortState'] = {
        'index': change.sortIndex,
        'ascending': change.sortAscending ?? false,
      };
    }
    var node = leaf;
    for (var i = change.path.length - 2; i >= 0; i--) {
      node = {'position': change.path[i], 'groupChange': node};
    }
    return node;
  }

  static KsSourceManga sourceMangaFromJson(
    Map<String, dynamic> json, {
    Uri Function(String path)? buildImageUrl,
    Map<String, String>? coverHeaders,
  }) {
    final thumbnailPath = json['thumbnailUrl'] as String?;
    return KsSourceManga(
      id: json['id'].toString(),
      title: json['title'] as String,
      coverUrl: thumbnailPath == null
          ? null
          : (buildImageUrl?.call(thumbnailPath) ?? Uri.parse(thumbnailPath))
              .toString(),
      coverHeaders: coverHeaders,
      description: json['description'] as String?,
      genres: (json['genre'] as List?)?.map((g) => g.toString()).toList() ??
          const [],
      inLibrary: json['inLibrary'] as bool? ?? false,
    );
  }

  static KsChapter chapterFromJson(Map<String, dynamic> json) {
    return KsChapter(
      id: json['id'].toString(),
      mangaId: json['mangaId'].toString(),
      title: json['name'] as String,
      chapterNumber: (json['chapterNumber'] as num?)?.toDouble() ?? 0,
      uploadDate: json['uploadDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              int.parse(json['uploadDate'].toString()))
          : null,
      read: json['isRead'] as bool? ?? false,
      lastPageRead: (json['lastPageRead'] as num?)?.toDouble(),
      pageCount: json['pageCount'] as int?,
      bookmarked: json['isBookmarked'] as bool? ?? false,
    );
  }

  static KsCategory categoryFromJson(Map<String, dynamic> json) {
    return KsCategory(
      id: json['id'].toString(),
      name: json['name'] as String,
      mangaCount: (json['mangas']?['totalCount'] as int?) ?? 0,
      isDefault: json['isDefaultCategory'] as bool? ?? false,
    );
  }

  /// [json] is a chapter node with its parent `manga { id title
  /// thumbnailUrl }`. `lastReadAt` arrives as a string of epoch SECONDS.
  static KsHistoryEntry historyEntryFromJson(
    Map<String, dynamic> json, {
    Uri Function(String path)? buildImageUrl,
    Map<String, String>? coverHeaders,
  }) {
    final manga = json['manga'] as Map<String, dynamic>;
    final thumbnailPath = manga['thumbnailUrl'] as String?;
    final pageCount = json['pageCount'] as int?;
    return KsHistoryEntry(
      mangaId: manga['id'].toString(),
      mangaTitle: manga['title'] as String,
      coverUrl: thumbnailPath == null
          ? null
          : (buildImageUrl?.call(thumbnailPath) ?? Uri.parse(thumbnailPath))
              .toString(),
      coverHeaders: coverHeaders,
      chapterId: json['id'].toString(),
      chapterTitle: json['name'] as String,
      chapterNumber: (json['chapterNumber'] as num?)?.toDouble(),
      lastPageRead: (json['lastPageRead'] as num?)?.toDouble(),
      // -1 means the server hasn't fetched the pages yet.
      pageCount: pageCount != null && pageCount > 0 ? pageCount : null,
      read: json['isRead'] as bool? ?? false,
      lastReadAt: DateTime.fromMillisecondsSinceEpoch(
          int.parse(json['lastReadAt'].toString()) * 1000),
    );
  }
}
