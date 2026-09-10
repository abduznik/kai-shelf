import '../models.dart';

/// Translates Komga's REST response shapes (SeriesDto + nested
/// SeriesMetadataDto, BookDto) into the shared DTOs.
class KomgaMappers {
  static MangaStatus mapStatus(String? raw) {
    switch (raw) {
      case 'ONGOING':
        return MangaStatus.ongoing;
      case 'ENDED':
        return MangaStatus.completed;
      case 'ABANDONED':
        return MangaStatus.cancelled;
      case 'HIATUS':
        return MangaStatus.onHiatus;
      default:
        return MangaStatus.unknown;
    }
  }

  static KsLibrary libraryFromJson(Map<String, dynamic> json) {
    return KsLibrary(id: json['id'] as String, name: json['name'] as String);
  }

  /// [json] is a Komga SeriesDto; title/summary/genres/status live in its
  /// nested `metadata` object (SeriesMetadataDto), not on SeriesDto itself.
  static KsManga mangaFromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] as Map<String, dynamic>? ?? {};
    return KsManga(
      id: json['id'] as String,
      title: (metadata['title'] as String?) ?? (json['name'] as String? ?? ''),
      description: metadata['summary'] as String?,
      genres:
          (metadata['genres'] as List?)?.map((g) => g.toString()).toList() ??
              const [],
      status: mapStatus(metadata['status'] as String?),
      lastUpdated: json['lastModified'] != null
          ? DateTime.tryParse(json['lastModified'] as String)
          : null,
      backendExtra: json,
    );
  }

  /// [json] is a Komga BookDto; read progress lives in its nested
  /// `readProgress` object (ReadProgressDto), which is null if unread.
  static KsChapter chapterFromJson(Map<String, dynamic> json) {
    final readProgress = json['readProgress'] as Map<String, dynamic>?;
    return KsChapter(
      id: json['id'] as String,
      mangaId: json['seriesId'] as String,
      title: json['name'] as String,
      chapterNumber: double.tryParse(json['number'].toString()) ?? 0,
      uploadDate: json['fileLastModified'] != null
          ? DateTime.tryParse(json['fileLastModified'] as String)
          : null,
      read: readProgress?['completed'] as bool? ?? false,
      lastPageRead: (readProgress?['page'] as num?)?.toDouble(),
    );
  }
}
