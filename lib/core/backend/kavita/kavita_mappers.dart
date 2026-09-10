import '../models.dart';

/// Translates Kavita's REST response shapes (SeriesDto + SeriesMetadataDto,
/// VolumeDto containing nested ChapterDto[]) into the shared DTOs. Kavita's
/// hierarchy is Series > Volumes > Chapters — we flatten volumes away and
/// treat each ChapterDto as a KsChapter.
class KavitaMappers {
  static KsLibrary libraryFromJson(Map<String, dynamic> json) {
    return KsLibrary(id: json['id'].toString(), name: json['name'] as String);
  }

  /// [json] is a Kavita SeriesDto; summary/genres live in a separate
  /// SeriesMetadataDto fetched via /api/Series/metadata, merged in here as
  /// [metadata] when available.
  static KsManga mangaFromJson(Map<String, dynamic> json,
      {Map<String, dynamic>? metadata}) {
    return KsManga(
      id: json['id'].toString(),
      title: (json['name'] as String?) ?? '',
      description: metadata?['summary'] as String?,
      genres: (metadata?['genres'] as List?)
              ?.map((g) => (g['title'] ?? g).toString())
              .toList() ??
          const [],
      backendExtra: json,
    );
  }

  /// [json] is a Kavita ChapterDto, taken from within a VolumeDto's nested
  /// `chapters` array.
  static KsChapter chapterFromJson(Map<String, dynamic> json,
      {required String mangaId}) {
    final pages = (json['pages'] as num?)?.toInt() ?? 0;
    final pagesRead = (json['pagesRead'] as num?)?.toInt() ?? 0;
    return KsChapter(
      id: json['id'].toString(),
      mangaId: mangaId,
      title: (json['title'] as String?)?.isNotEmpty == true
          ? json['title'] as String
          : 'Chapter ${json['number']}',
      chapterNumber: double.tryParse(json['number'].toString()) ?? 0,
      uploadDate: json['releaseDate'] != null
          ? DateTime.tryParse(json['releaseDate'] as String)
          : null,
      read: pages > 0 && pagesRead >= pages,
      lastPageRead: pagesRead.toDouble(),
      pageCount: pages,
    );
  }
}
