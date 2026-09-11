/// Raw GraphQL documents for the Suwayomi adapter. Kept as plain strings
/// (no .graphql/codegen pipeline yet) to keep the dependency footprint small
/// for a solo-maintained project at this stage.
class SuwayomiQueries {
  static const aboutQuery = r'''
    query About {
      aboutServer {
        buildType
        version
      }
    }
  ''';

  static const categoryListQuery = r'''
    query CategoryList {
      categories {
        nodes {
          id
          name
          mangas {
            totalCount
          }
        }
      }
    }
  ''';

  /// Lists in-library manga, optionally filtered by title. Does NOT filter
  /// by category — Suwayomi's MangaFilterInput.categoryId does not
  /// correspond to a manga's actual category membership (confirmed against
  /// a live server: manga clearly listed under a category via
  /// `category(id:).mangas` came back with categoryId filters matching
  /// nothing). Category-scoped listing goes through [categoryMangaListQuery]
  /// instead.
  static const mangaListQuery = r'''
    query MangaList($searchQuery: String) {
      mangas(
        filter: { inLibrary: { equalTo: true }, title: { includesInsensitive: $searchQuery } }
      ) {
        nodes {
          id
          title
          thumbnailUrl
          description
          genre
          status
          lastFetchedAt
        }
      }
    }
  ''';

  /// Lists manga belonging to one category via the category's own `mangas`
  /// relation. This field takes no filter args, so a [searchQuery] (if
  /// any) must be applied client-side against the returned nodes.
  static const categoryMangaListQuery = r'''
    query CategoryMangaList($categoryId: Int!) {
      category(id: $categoryId) {
        mangas {
          nodes {
            id
            title
            thumbnailUrl
            description
            genre
            status
            lastFetchedAt
          }
        }
      }
    }
  ''';

  static const mangaDetailQuery = r'''
    query MangaDetail($id: Int!) {
      manga(id: $id) {
        id
        title
        thumbnailUrl
        description
        genre
        status
        lastFetchedAt
      }
    }
  ''';

  static const chapterListQuery = r'''
    query ChapterList($mangaId: Int!) {
      chapters(condition: { mangaId: $mangaId }) {
        nodes {
          id
          mangaId
          name
          chapterNumber
          uploadDate
          isRead
          lastPageRead
          pageCount
        }
      }
    }
  ''';

  /// Suwayomi fetches chapter pages lazily: `chapter(id:).pageCount` is -1
  /// until this mutation has run at least once for that chapter (confirmed
  /// against a live server). The returned `pages` list is the actual,
  /// correct set of page paths — building them by hand from mangaId +
  /// chapter number is fragile and unnecessary once this has been called.
  static const fetchChapterPagesMutation = r'''
    mutation FetchChapterPages($chapterId: Int!) {
      fetchChapterPages(input: { chapterId: $chapterId }) {
        pages
      }
    }
  ''';

  static const updateChapterMutation = r'''
    mutation UpdateChapter($id: Int!, $isRead: Boolean, $lastPageRead: Int) {
      updateChapter(
        input: {
          id: $id
          patch: { isRead: $isRead, lastPageRead: $lastPageRead }
        }
      ) {
        chapter {
          id
        }
      }
    }
  ''';
}
