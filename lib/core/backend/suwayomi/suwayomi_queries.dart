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

  static const loginMutation = r'''
    mutation Login($username: String!, $password: String!) {
      login(input: { username: $username, password: $password }) {
        accessToken
        refreshToken
      }
    }
  ''';

  static const refreshTokenMutation = r'''
    mutation RefreshToken($refreshToken: String!) {
      refreshToken(input: { refreshToken: $refreshToken }) {
        accessToken
        refreshToken
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

  static const mangaListQuery = r'''
    query MangaList($categoryId: Int, $searchQuery: String) {
      mangas(
        filter: { inLibrary: { equalTo: true } }
        condition: { categoryId: $categoryId }
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

  static const chapterPagesQuery = r'''
    query ChapterPages($id: Int!) {
      chapter(id: $id) {
        id
        pageCount
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
