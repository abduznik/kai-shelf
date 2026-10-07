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
  static KsManga mangaFromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? metadata,
    Uri Function(String path)? buildImageUrl,
    Map<String, String>? coverHeaders,
  }) {
    final id = json['id'].toString();
    return KsManga(
      id: id,
      title: (json['name'] as String?) ?? '',
      coverUrl: buildImageUrl
          ?.call('/api/Image/series-cover?seriesId=$id')
          .toString(),
      coverHeaders: coverHeaders,
      description: metadata?['summary'] as String?,
      genres: (metadata?['genres'] as List?)
              ?.map((g) => (g['title'] ?? g).toString())
              .toList() ??
          const [],
      backendExtra: json,
    );
  }

  /// Kavita stamps UTC times without a zone suffix ("...T15:17:09.80"), which
  /// Dart would otherwise read as local time. Returns null for the
  /// 0001-01-01 placeholder meaning "never".
  static DateTime? parseUtc(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    final hasZone =
        raw.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(raw);
    final parsed = DateTime.tryParse(hasZone ? raw : '${raw}Z');
    if (parsed == null || parsed.year <= 1) return null;
    return parsed.toLocal();
  }

  /// A chapter that has reading progress, paired with its series. Returns
  /// null for a chapter never opened. [series] is the owning SeriesDto and
  /// [volume] the VolumeDto [json] came from.
  static KsHistoryEntry? historyEntryFromJson(
    Map<String, dynamic> json, {
    required Map<String, dynamic> series,
    Map<String, dynamic>? volume,
    Uri Function(String path)? buildImageUrl,
    Map<String, String>? coverHeaders,
  }) {
    final lastReadAt = parseUtc(json['lastReadingProgressUtc']);
    if (lastReadAt == null) return null;
    final seriesId = series['id'].toString();
    final chapter = chapterFromJson(json, mangaId: seriesId, volume: volume);
    return KsHistoryEntry(
      mangaId: seriesId,
      mangaTitle: (series['name'] as String?) ?? '',
      coverUrl: buildImageUrl
          ?.call('/api/Image/series-cover?seriesId=$seriesId')
          .toString(),
      coverHeaders: coverHeaders,
      chapterId: chapter.id,
      chapterTitle: chapter.title,
      chapterNumber: chapter.chapterNumber,
      lastPageRead: chapter.lastPageRead,
      pageCount: chapter.pageCount,
      read: chapter.read,
      lastReadAt: lastReadAt,
    );
  }

  /// [json] is a Kavita ChapterDto, taken from within a VolumeDto's nested
  /// `chapters` array.
  ///
  /// Kavita marks "no chapter number" (volume-only releases, which is how
  /// most CBZ/EPUB libraries look) with the sentinel -100000, in both
  /// `number` and `title`. Those fall back to the owning volume's number so
  /// they read "Volume 1" and sort correctly instead of showing "-100000".
  static KsChapter chapterFromJson(Map<String, dynamic> json,
      {required String mangaId, Map<String, dynamic>? volume}) {
    final pages = (json['pages'] as num?)?.toInt() ?? 0;
    final pagesRead = (json['pagesRead'] as num?)?.toInt() ?? 0;
    final number = double.tryParse(json['number'].toString()) ?? 0;
    final volumeOnly = number <= -100000 || json['title'] == '-100000';
    final volumeNumber = double.tryParse('${volume?['number'] ?? ''}');
    final title = (json['title'] as String?);
    return KsChapter(
      id: json['id'].toString(),
      mangaId: mangaId,
      title: volumeOnly
          ? (volume?['name'] != null
              ? 'Volume ${volume!['name']}'
              : 'Volume ${volumeNumber?.toStringAsFixed(0) ?? ''}'.trim())
          : (title != null && title.isNotEmpty
              ? title
              : 'Chapter ${json['number']}'),
      chapterNumber: volumeOnly ? (volumeNumber ?? 0) : number,
      uploadDate: json['releaseDate'] != null
          ? DateTime.tryParse(json['releaseDate'] as String)
          : null,
      read: pages > 0 && pagesRead >= pages,
      lastPageRead: pagesRead.toDouble(),
      pageCount: pages,
    );
  }
}
