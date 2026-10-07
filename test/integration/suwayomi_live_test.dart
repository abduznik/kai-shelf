@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/auth_credentials.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/suwayomi/suwayomi_backend.dart';

/// Exercises the Suwayomi adapter against a real server. Skipped unless
/// KAI_SUWAYOMI_URL is set (CI starts a Suwayomi container for it), e.g.
///   KAI_SUWAYOMI_URL=http://localhost:4567 flutter test test/integration
void main() {
  final url = Platform.environment['KAI_SUWAYOMI_URL'];
  final skip = url == null ? 'KAI_SUWAYOMI_URL not set' : null;

  const repoUrl =
      'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json';
  const mangadex = 'eu.kanade.tachiyomi.extension.all.mangadex';

  late SuwayomiBackend backend;

  setUpAll(() async {
    if (url == null) return;
    backend = SuwayomiBackend(ServerConnectionInfo(
      serverId: 'live',
      displayName: 'live',
      baseUrl: Uri.parse(url),
      type: BackendType.suwayomi,
    ));
    final auth = await backend.login(const SuwayomiCredentials());
    expect(auth.success, isTrue);
  });

  test('add repo, refresh, install, browse, search, filter, uninstall',
      () async {
    if (!(await backend.getExtensionRepos())
        .any((r) => r.indexUrl == repoUrl)) {
      await backend.addExtensionRepo(repoUrl);
    }
    final repos = await backend.getExtensionRepos();
    expect(repos, isNotEmpty);

    final all = await backend.getExtensions(refresh: true);
    expect(all.length, greaterThan(100));
    final dex = all.firstWhere((e) => e.pkgName == mangadex);
    expect(dex.contentWarning, isNot(ContentWarning.unknown));

    await backend.installExtension(mangadex);
    final installed = (await backend.getExtensions())
        .firstWhere((e) => e.pkgName == mangadex);
    expect(installed.isInstalled, isTrue);

    final sources = await backend.getSources();
    final en =
        sources.firstWhere((s) => s.name == 'MangaDex' && s.lang == 'en');

    final popular = await backend.browseSource(en.id);
    expect(popular.items, isNotEmpty);
    expect(popular.hasNextPage, isTrue);
    final page2 = await backend.browseSource(en.id, page: 2);
    expect(page2.items.first.id, isNot(popular.items.first.id));

    final filters = await backend.getSourceFilters(en.id);
    expect(filters, isNotEmpty);
    expect(filters.whereType<KsGroupFilter>(), isNotEmpty);
    expect(filters.whereType<KsSortFilter>(), isNotEmpty);

    // Include the first tri-state tag nested in a group and sort by title.
    KsTriStateFilter? tri;
    List<int> triPath = [];
    for (final f in filters.whereType<KsGroupFilter>()) {
      for (final c in f.children) {
        if (c is KsTriStateFilter && tri == null) {
          tri = c;
          triPath = [f.position, c.position];
        }
      }
    }
    final sort = filters.whereType<KsSortFilter>().first;
    final result = await backend.browseSource(
      en.id,
      mode: SourceBrowseMode.search,
      query: 'one piece',
      filters: [
        KsFilterChange(
            path: [sort.position], sortIndex: 0, sortAscending: true),
        if (tri != null)
          KsFilterChange(path: triPath, triState: KsTriState.ignore),
      ],
    );
    expect(result.items, isNotEmpty);

    // Preview: read a title straight from search, without adding it.
    final plain = await backend.browseSource(en.id,
        mode: SourceBrowseMode.search, query: 'one piece');
    // Plenty of MangaDex titles and chapters are external links with no
    // readable pages, so search for the first pair that has some.
    KsSourceManga? preview;
    List<KsPage> pages = [];
    outer:
    for (final m in plain.items.where((m) => !m.inLibrary).take(8)) {
      final chapters = await backend.getChapters(m.id);
      for (final c in chapters.take(5)) {
        pages = await backend.getPages(c.id);
        if (pages.isNotEmpty) {
          preview = m;
          break outer;
        }
      }
    }
    expect(preview, isNotNull, reason: 'no previewable title found');
    final detail = await backend.getMangaDetail(preview!.id);
    expect(detail.inLibrary, isFalse);
    expect(detail.description, isNotEmpty);
    expect((await backend.getMangaDetail(preview.id)).inLibrary, isFalse);

    await backend.uninstallExtension(mangadex);
    final after = (await backend.getExtensions())
        .firstWhere((e) => e.pkgName == mangadex);
    expect(after.isInstalled, isFalse);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  // Uses Suwayomi's built-in local source (CBZ files under the server's
  // local folder; run.sh mounts the test comics there), so it needs no
  // extension or network access.
  test('history lists read chapters newest first', () async {
    final local = await backend.browseSource('0');
    if (local.items.isEmpty) {
      markTestSkipped('server has no local-source comics');
      return;
    }
    final manga = local.items.firstWhere((m) => m.title == 'Beta Quest');
    await backend.addToLibrary(manga.id);
    final chapters = await backend.getChapters(manga.id);
    expect(chapters.length, 3);

    // Opening a chapter's pages is what gives the server its page count, and
    // the server only keeps a page index it can check against that count.
    for (final c in chapters) {
      expect(await backend.getPages(c.id), hasLength(4));
    }

    // lastReadAt has one-second resolution, so space the reads.
    await backend.updateReadProgress(chapters[0].id,
        read: false, lastPageRead: 1);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await backend.updateReadProgress(chapters[1].id,
        read: false, lastPageRead: 2);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await backend.updateReadProgress(chapters[2].id,
        read: true, lastPageRead: 3);

    final history = await backend.getHistory(limit: 20);
    expect(history.take(3).map((e) => e.chapterId),
        [chapters[2].id, chapters[1].id, chapters[0].id]);
    expect(history.first.read, isTrue);
    expect(history.first.mangaTitle, 'Beta Quest');
    expect(history.first.mangaId, manga.id);
    expect(history[1].lastPageRead, 2);
    expect(history[1].pageCount, 4);
    expect(history[0].lastReadAt.isAfter(history[1].lastReadAt), isTrue);

    final second = await backend.getHistory(limit: 2, offset: 2);
    expect(second.first.chapterId, history[2].chapterId);
  }, skip: skip);
}
