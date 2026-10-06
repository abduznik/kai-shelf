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

  /// Lists installed sources (extensions) — the "catalogs" a user can
  /// search to discover manga not yet in their library, same concept as
  /// Tachiyomi/Mihon's source browser.
  static const sourceListQuery = r'''
    query SourceList {
      sources {
        nodes {
          id
          name
          lang
          iconUrl
          displayName
          supportsLatest
          contentWarning
        }
      }
    }
  ''';

  /// Searches one source's catalog by title. `fetchSourceManga` covers both
  /// browsing (empty query) and searching (non-empty query) via the same
  /// field, differentiated by `type`.
  static const sourceSearchQuery = r'''
    query SourceSearch($sourceId: LongString!, $searchQuery: String!, $page: Int!) {
      fetchSourceManga(
        input: { source: $sourceId, type: SEARCH, query: $searchQuery, page: $page }
      ) {
        mangas {
          id
          title
          thumbnailUrl
          description
          genre
          status
          inLibrary
        }
        hasNextPage
      }
    }
  ''';

  /// Adds a source-catalog result to the local library. Suwayomi tracks
  /// library membership as a boolean flag on the manga itself (there's no
  /// separate "add" mutation) — confirmed against the schema's
  /// UpdateMangaPatch.inLibrary field.
  static const addMangaToLibraryMutation = r'''
    mutation AddMangaToLibrary($id: Int!) {
      updateManga(input: { id: $id, patch: { inLibrary: true } }) {
        manga {
          id
          inLibrary
        }
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

  static const _extensionFields = '''
    pkgName
    name
    lang
    versionName
    iconUrl
    isInstalled
    hasUpdate
    isObsolete
    contentWarning
    extensionStore {
      name
    }
  ''';

  static const extensionListQuery = '''
    query ExtensionList {
      extensions {
        nodes {
          $_extensionFields
        }
      }
    }
  ''';

  /// Re-reads every repository index, then returns the refreshed list.
  static const fetchExtensionsMutation = '''
    mutation FetchExtensions {
      fetchExtensions(input: {}) {
        extensions {
          $_extensionFields
        }
      }
    }
  ''';

  static const updateExtensionMutation = r'''
    mutation UpdateExtension($id: String!, $patch: UpdateExtensionPatchInput!) {
      updateExtension(input: { id: $id, patch: $patch }) {
        extension {
          pkgName
          isInstalled
        }
      }
    }
  ''';

  static const extensionStoreListQuery = r'''
    query ExtensionStores {
      extensionStores {
        nodes {
          name
          indexUrl
        }
      }
    }
  ''';

  static const addExtensionStoreMutation = r'''
    mutation AddExtensionStore($indexUrl: String!) {
      addExtensionStore(input: { indexUrl: $indexUrl }) {
        clientMutationId
      }
    }
  ''';

  static const removeExtensionStoreMutation = r'''
    mutation RemoveExtensionStore($indexUrl: String!) {
      removeExtensionStore(input: { indexUrl: $indexUrl }) {
        clientMutationId
      }
    }
  ''';

  // Fields are aliased per filter kind because GraphQL rejects the same
  // response key with different types across union fragments.
  static const _filterLeaf = '''
    __typename
    ... on HeaderFilter { hName: name }
    ... on SeparatorFilter { sName: name }
    ... on TextFilter { tName: name textDefault: default }
    ... on CheckBoxFilter { cName: name checkDefault: default }
    ... on TriStateFilter { triName: name triDefault: default }
    ... on SelectFilter { selName: name selDefault: default selValues: values }
    ... on SortFilter { sortName: name sortDefault: default { index ascending } sortValues: values }
  ''';

  /// A source's filters in their default state. Groups are expanded three
  /// levels deep, which covers every extension seen in the wild.
  static const sourceFiltersQuery = '''
    query SourceFilters(\$id: LongString!) {
      source(id: \$id) {
        filters {
          $_filterLeaf
          ... on GroupFilter {
            gName: name
            groupFilters: filters {
              $_filterLeaf
              ... on GroupFilter {
                gName: name
                groupFilters: filters {
                  $_filterLeaf
                }
              }
            }
          }
        }
      }
    }
  ''';

  static const sourceBrowseMutation = r'''
    mutation SourceBrowse($sourceId: LongString!, $type: FetchSourceMangaType!, $query: String, $page: Int!, $filters: [FilterChangeInput!]) {
      fetchSourceManga(
        input: { source: $sourceId, type: $type, query: $query, page: $page, filters: $filters }
      ) {
        mangas {
          id
          title
          thumbnailUrl
          description
          genre
          status
          inLibrary
        }
        hasNextPage
      }
    }
  ''';

  static const removeMangaFromLibraryMutation = r'''
    mutation RemoveMangaFromLibrary($id: Int!) {
      updateManga(input: { id: $id, patch: { inLibrary: false } }) {
        manga {
          id
          inLibrary
        }
      }
    }
  ''';
}
