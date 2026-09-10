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

  static KsManga mangaFromJson(Map<String, dynamic> json) {
    return KsManga(
      id: json['id'].toString(),
      title: json['title'] as String,
      coverUrl: json['thumbnailUrl'] as String?,
      description: json['description'] as String?,
      genres: (json['genre'] as List?)?.map((g) => g.toString()).toList() ??
          const [],
      status: mapStatus(json['status'] as String?),
      lastUpdated: json['lastFetchedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              int.parse(json['lastFetchedAt'].toString()))
          : null,
      backendExtra: json,
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
    );
  }
}
