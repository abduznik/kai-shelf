enum BackendType { suwayomi, komga, kavita }

enum MangaStatus {
  unknown,
  ongoing,
  completed,
  licensed,
  publishingFinished,
  cancelled,
  onHiatus
}

class KsLibrary {
  const KsLibrary({required this.id, required this.name, this.mangaCount = 0});

  final String id;
  final String name;
  final int mangaCount;
}

/// A user-named grouping of manga: a Suwayomi category, a Komga collection or
/// a Kavita collection. Distinct from [KsLibrary], which for Komga/Kavita is
/// a disk-backed library the user cannot edit.
class KsCategory {
  const KsCategory({
    required this.id,
    required this.name,
    this.mangaCount = 0,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final int mangaCount;

  /// Suwayomi's built-in "Default" category, which holds every library manga
  /// that has no category of its own. It cannot be renamed, moved or deleted.
  final bool isDefault;
}

class KsManga {
  const KsManga({
    required this.id,
    required this.title,
    this.coverUrl,
    this.coverHeaders,
    this.description,
    this.genres = const [],
    this.status = MangaStatus.unknown,
    this.lastUpdated,
    this.inLibrary = true,
    this.backendExtra = const {},
  });

  final String id;
  final String title;
  final String? coverUrl;

  /// Auth headers required to fetch [coverUrl], for the same reason
  /// [KsPage.extraHeaders] exists — confirmed against a live Suwayomi
  /// BASIC_AUTH instance, where the thumbnail endpoint 401s without them
  /// just like the GraphQL/page endpoints do.
  final Map<String, String>? coverHeaders;
  final String? description;
  final List<String> genres;
  final MangaStatus status;
  final DateTime? lastUpdated;

  /// False for a title opened from a source search that hasn't been added
  /// to the library yet (it can still be read, just not tracked).
  final bool inLibrary;

  /// Escape hatch for backend-specific fields that don't warrant a shared field.
  final Map<String, dynamic> backendExtra;
}

class KsChapter {
  const KsChapter({
    required this.id,
    required this.mangaId,
    required this.title,
    required this.chapterNumber,
    this.uploadDate,
    this.read = false,
    this.lastPageRead,
    this.pageCount,
    this.bookmarked = false,
  });

  final String id;
  final String mangaId;
  final String title;
  final double chapterNumber;
  final DateTime? uploadDate;
  final bool read;
  final double? lastPageRead;
  final int? pageCount;

  /// Only Suwayomi tracks bookmarks per chapter; Komga and Kavita bookmark
  /// individual pages instead, so this stays false for them.
  final bool bookmarked;
}

class KsPage {
  const KsPage({
    required this.index,
    required this.imageUrl,
    this.extraHeaders,
    this.localPath,
  });

  final int index;
  final String imageUrl;

  /// Auth headers (cookie/bearer/api-key) required to fetch [imageUrl], since
  /// Komga/Kavita image endpoints need per-request auth that plain
  /// cached_network_image URL fetches wouldn't otherwise carry.
  final Map<String, String>? extraHeaders;

  /// Set when this page has been downloaded — readers should load from
  /// this file instead of fetching [imageUrl] over the network.
  final String? localPath;

  bool get isLocal => localPath != null;
}

/// A source/extension catalog that can be browsed or searched to discover
/// manga not yet in the local library. Only meaningful for backends that
/// have this concept (Suwayomi) — Komga/Kavita just index whatever's
/// already on disk, so there is nothing to "discover" there.
class KsSource {
  const KsSource({
    required this.id,
    required this.name,
    this.lang,
    this.iconUrl,
    this.displayName,
    this.supportsLatest = true,
    this.contentWarning = ContentWarning.unknown,
  });

  final String id;
  final String name;
  final String? lang;
  final String? iconUrl;

  /// Name with the language folded in ("MangaDex (EN)"), when the server
  /// provides one — distinguishes same-named sources of different languages.
  final String? displayName;
  final bool supportsLatest;
  final ContentWarning contentWarning;

  String get label => displayName ?? name;
}

/// A search/browse result from a source catalog, distinct from [KsManga]
/// (an in-library manga) because it may not have a library-scoped id or
/// full metadata until actually added.
class KsSourceManga {
  const KsSourceManga({
    required this.id,
    required this.title,
    this.coverUrl,
    this.coverHeaders,
    this.description,
    this.genres = const [],
    this.inLibrary = false,
  });

  final String id;
  final String title;
  final String? coverUrl;
  final Map<String, String>? coverHeaders;
  final String? description;
  final List<String> genres;
  final bool inLibrary;
}

class KsUser {
  const KsUser(
      {required this.id, required this.displayName, this.isAdmin = false});

  final String id;
  final String displayName;
  final bool isAdmin;
}

/// Persisted, session-carrying connection state for one configured server.
class ServerConnectionInfo {
  const ServerConnectionInfo({
    required this.serverId,
    required this.displayName,
    required this.baseUrl,
    required this.type,
    this.sessionToken,
    this.refreshToken,
    this.apiKey,
    this.extraHeaders = const {},
  });

  final String serverId;
  final String displayName;
  final Uri baseUrl;
  final BackendType type;
  final String? sessionToken;

  /// Long-lived token used to mint a new [sessionToken] once it expires
  /// (Suwayomi's access/refresh JWT pair).
  final String? refreshToken;
  final String? apiKey;
  final Map<String, String> extraHeaders;

  Map<String, dynamic> toJson() => {
        'serverId': serverId,
        'displayName': displayName,
        'baseUrl': baseUrl.toString(),
        'type': type.name,
        'sessionToken': sessionToken,
        'refreshToken': refreshToken,
        'apiKey': apiKey,
        'extraHeaders': extraHeaders,
      };

  factory ServerConnectionInfo.fromJson(Map<String, dynamic> json) {
    return ServerConnectionInfo(
      serverId: json['serverId'] as String,
      displayName: json['displayName'] as String,
      baseUrl: Uri.parse(json['baseUrl'] as String),
      type: BackendType.values.byName(json['type'] as String),
      sessionToken: json['sessionToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      apiKey: json['apiKey'] as String?,
      extraHeaders:
          (json['extraHeaders'] as Map?)?.cast<String, String>() ?? const {},
    );
  }

  ServerConnectionInfo copyWith({
    String? sessionToken,
    String? refreshToken,
    String? apiKey,
    Map<String, String>? extraHeaders,
  }) {
    return ServerConnectionInfo(
      serverId: serverId,
      displayName: displayName,
      baseUrl: baseUrl,
      type: type,
      sessionToken: sessionToken ?? this.sessionToken,
      refreshToken: refreshToken ?? this.refreshToken,
      apiKey: apiKey ?? this.apiKey,
      extraHeaders: extraHeaders ?? this.extraHeaders,
    );
  }
}

enum ContentWarning { safe, mixed, nsfw, unknown }

/// A source extension in an extension store, installed or not.
class KsExtension {
  const KsExtension({
    required this.pkgName,
    required this.name,
    this.lang,
    this.versionName,
    this.iconUrl,
    this.isInstalled = false,
    this.hasUpdate = false,
    this.isObsolete = false,
    this.contentWarning = ContentWarning.unknown,
    this.storeName,
  });

  final String pkgName;
  final String name;
  final String? lang;
  final String? versionName;
  final String? iconUrl;
  final bool isInstalled;
  final bool hasUpdate;
  final bool isObsolete;
  final ContentWarning contentWarning;
  final String? storeName;
}

/// An extension repository ("store") the server pulls extensions from.
class KsExtensionRepo {
  const KsExtensionRepo({required this.indexUrl, required this.name});

  final String indexUrl;
  final String name;
}

/// Which listing of a source to browse.
enum SourceBrowseMode { popular, latest, search }

class KsSourceFilterOption {
  const KsSourceFilterOption(this.label);

  final String label;
}

/// One filter a source exposes (genre pickers, sort order, status, ...).
/// Sources define their own sets, so filters are described generically and
/// rendered dynamically. [position] is the index within its parent list,
/// which is how servers address a filter when it is changed.
sealed class KsSourceFilter {
  const KsSourceFilter({required this.name, required this.position});

  final String name;
  final int position;
}

class KsHeaderFilter extends KsSourceFilter {
  const KsHeaderFilter({required super.name, required super.position});
}

class KsSeparatorFilter extends KsSourceFilter {
  const KsSeparatorFilter({required super.name, required super.position});
}

class KsTextFilter extends KsSourceFilter {
  const KsTextFilter(
      {required super.name, required super.position, this.value = ''});

  final String value;
}

class KsCheckBoxFilter extends KsSourceFilter {
  const KsCheckBoxFilter(
      {required super.name, required super.position, this.value = false});

  final bool value;
}

enum KsTriState { ignore, include, exclude }

class KsTriStateFilter extends KsSourceFilter {
  const KsTriStateFilter(
      {required super.name,
      required super.position,
      this.value = KsTriState.ignore});

  final KsTriState value;
}

class KsSelectFilter extends KsSourceFilter {
  const KsSelectFilter(
      {required super.name,
      required super.position,
      required this.options,
      this.selected = 0});

  final List<String> options;
  final int selected;
}

class KsSortFilter extends KsSourceFilter {
  const KsSortFilter(
      {required super.name,
      required super.position,
      required this.options,
      this.selected = 0,
      this.ascending = false});

  final List<String> options;
  final int selected;
  final bool ascending;
}

class KsGroupFilter extends KsSourceFilter {
  const KsGroupFilter(
      {required super.name, required super.position, required this.children});

  final List<KsSourceFilter> children;
}

/// A single user edit to a source filter, addressed by position path
/// (outermost group first). Value fields mirror the filter kinds.
class KsFilterChange {
  const KsFilterChange({
    required this.path,
    this.checkBox,
    this.triState,
    this.select,
    this.text,
    this.sortIndex,
    this.sortAscending,
  });

  final List<int> path;
  final bool? checkBox;
  final KsTriState? triState;
  final int? select;
  final String? text;
  final int? sortIndex;
  final bool? sortAscending;
}

class KsSourcePage {
  const KsSourcePage({required this.items, required this.hasNextPage});

  final List<KsSourceManga> items;
  final bool hasNextPage;
}
