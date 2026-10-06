import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/features/library/domain/library_filter.dart';
import 'package:kai_shelf/features/library/domain/source_filter.dart';

KsManga m(String title,
        {MangaStatus status = MangaStatus.unknown,
        List<String> genres = const [],
        int? updated}) =>
    KsManga(
      id: title,
      title: title,
      status: status,
      genres: genres,
      lastUpdated:
          updated == null ? null : DateTime.fromMillisecondsSinceEpoch(updated),
    );

void main() {
  final library = [
    m('Berserk',
        status: MangaStatus.ongoing,
        genres: ['Action', 'Dark Fantasy'],
        updated: 3),
    m('akira',
        status: MangaStatus.completed,
        genres: ['Action', 'Sci-Fi'],
        updated: 1),
    m('Chobits',
        status: MangaStatus.completed, genres: ['Romance'], updated: 2),
  ];

  group('LibraryFilter', () {
    test('sorts titles case-insensitively by default', () {
      expect(const LibraryFilter().apply(library).map((e) => e.title),
          ['akira', 'Berserk', 'Chobits']);
    });

    test('sorts by recently updated, unknown dates last', () {
      final list = [...library, m('Zed')];
      final sorted = const LibraryFilter(sort: LibrarySort.recentlyUpdated)
          .apply(list)
          .map((e) => e.title);
      expect(sorted, ['Berserk', 'Chobits', 'akira', 'Zed']);
    });

    test('filters by status', () {
      final r =
          const LibraryFilter(statuses: {MangaStatus.completed}).apply(library);
      expect(r.map((e) => e.title), ['akira', 'Chobits']);
    });

    test('include genres require all, exclude drops any, case-insensitive', () {
      expect(
          const LibraryFilter(includeGenres: {'action', 'sci-fi'})
              .apply(library)
              .map((e) => e.title),
          ['akira']);
      expect(
          const LibraryFilter(excludeGenres: {'ACTION'})
              .apply(library)
              .map((e) => e.title),
          ['Chobits']);
    });

    test('text query combines with other filters', () {
      final r =
          const LibraryFilter(query: 'a', statuses: {MangaStatus.completed})
              .apply(library);
      expect(r.map((e) => e.title), ['akira']);
    });

    test('genresOf dedupes case-insensitively and sorts', () {
      expect(LibraryFilter.genresOf(library),
          ['Action', 'Dark Fantasy', 'Romance', 'Sci-Fi']);
    });

    test('activeCount counts narrowing options', () {
      expect(const LibraryFilter().activeCount, 0);
      expect(
          const LibraryFilter(
                  statuses: {MangaStatus.ongoing},
                  includeGenres: {'a'},
                  sort: LibrarySort.titleDesc)
              .activeCount,
          3);
    });
  });

  group('SourceListFilter', () {
    const sources = [
      KsSource(
          id: '1', name: 'MangaDex', lang: 'en', displayName: 'MangaDex (EN)'),
      KsSource(
          id: '2', name: 'MangaDex', lang: 'fr', displayName: 'MangaDex (FR)'),
      KsSource(
          id: '3',
          name: 'Spicy',
          lang: 'en',
          contentWarning: ContentWarning.nsfw),
    ];

    test('filters by language, nsfw and name', () {
      expect(const SourceListFilter(languages: {'fr'}).apply(sources).single.id,
          '2');
      expect(
          const SourceListFilter(hideNsfw: true)
              .apply(sources)
              .map((s) => s.id),
          ['1', '2']);
      expect(
          const SourceListFilter(query: 'spic').apply(sources).single.id, '3');
      expect(SourceListFilter.languagesOf(sources), ['en', 'fr']);
    });
  });
}
