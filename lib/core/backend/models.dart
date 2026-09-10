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

class KsManga {
  const KsManga({
    required this.id,
    required this.title,
    this.coverUrl,
    this.description,
    this.genres = const [],
    this.status = MangaStatus.unknown,
    this.lastUpdated,
    this.backendExtra = const {},
  });

  final String id;
  final String title;
  final String? coverUrl;
  final String? description;
  final List<String> genres;
  final MangaStatus status;
  final DateTime? lastUpdated;

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
  });

  final String id;
  final String mangaId;
  final String title;
  final double chapterNumber;
  final DateTime? uploadDate;
  final bool read;
  final double? lastPageRead;
  final int? pageCount;
}

class KsPage {
  const KsPage(
      {required this.index, required this.imageUrl, this.extraHeaders});

  final int index;
  final String imageUrl;

  /// Auth headers (cookie/bearer/api-key) required to fetch [imageUrl], since
  /// Komga/Kavita image endpoints need per-request auth that plain
  /// cached_network_image URL fetches wouldn't otherwise carry.
  final Map<String, String>? extraHeaders;
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
    this.apiKey,
    this.extraHeaders = const {},
  });

  final String serverId;
  final String displayName;
  final Uri baseUrl;
  final BackendType type;
  final String? sessionToken;
  final String? apiKey;
  final Map<String, String> extraHeaders;

  ServerConnectionInfo copyWith({
    String? sessionToken,
    String? apiKey,
    Map<String, String>? extraHeaders,
  }) {
    return ServerConnectionInfo(
      serverId: serverId,
      displayName: displayName,
      baseUrl: baseUrl,
      type: type,
      sessionToken: sessionToken ?? this.sessionToken,
      apiKey: apiKey ?? this.apiKey,
      extraHeaders: extraHeaders ?? this.extraHeaders,
    );
  }
}
