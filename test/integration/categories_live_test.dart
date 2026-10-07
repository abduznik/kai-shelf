@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/auth_credentials.dart';
import 'package:kai_shelf/core/backend/kavita/kavita_backend.dart';
import 'package:kai_shelf/core/backend/komga/komga_backend.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/core/backend/server_backend.dart';
import 'package:kai_shelf/core/backend/suwayomi/suwayomi_backend.dart';

/// Category/collection CRUD against real servers. Each group is skipped
/// unless its server's env vars are set (see tools/integration/run.sh).
/// Suwayomi additionally needs a title in its Local source, which run.sh
/// seeds by copying a comic into the container.
void main() {
  final env = Platform.environment;
  final stamp = DateTime.now().millisecondsSinceEpoch;

  ServerConnectionInfo info(String url, BackendType type) =>
      ServerConnectionInfo(
        serverId: 'live',
        displayName: 'live',
        baseUrl: Uri.parse(url),
        type: type,
      );

  Future<void> removeAll(
      CategoryCapableBackend b, Iterable<String> names) async {
    for (final c in await b.getCategories()) {
      if (names.contains(c.name)) await b.deleteCategory(c.id);
    }
  }

  group('Suwayomi categories', () {
    final url = env['KAI_SUWAYOMI_URL'];
    final skip = url == null ? 'KAI_SUWAYOMI_URL not set' : null;
    late SuwayomiBackend backend;
    final a = 'It A $stamp';
    final b = 'It B $stamp';

    setUpAll(() async {
      if (skip != null) return;
      backend = SuwayomiBackend(info(url!, BackendType.suwayomi));
      expect(
          (await backend.login(const SuwayomiCredentials())).success, isTrue);
    });
    tearDownAll(() async {
      if (skip == null) await removeAll(backend, [a, b, '$a renamed']);
    });

    test('create, rename, reorder, assign, bookmark, delete', () async {
      final catA = await backend.createCategory(a);
      final catB = await backend.createCategory(b);
      expect(catA.isDefault, isFalse);

      var all = await backend.getCategories();
      expect(all.first.isDefault, isTrue);
      expect(all.map((c) => c.name), containsAll([a, b]));

      await backend.renameCategory(catA.id, '$a renamed');
      all = await backend.getCategories();
      expect(all.map((c) => c.name), contains('$a renamed'));

      // B starts after A; move it to the front of the editable ones.
      await backend.moveCategory(catB.id, 0);
      final order = (await backend.getCategories()).map((c) => c.id).toList();
      expect(order.indexOf(catB.id), lessThan(order.indexOf(catA.id)));
      expect(order.first, all.first.id, reason: 'default stays first');

      // A title from the Local source stands in for a library manga.
      final page = await backend.browseSource('0');
      expect(page.items, isNotEmpty,
          reason: 'seed a comic into the Local source (see run.sh)');
      final manga = page.items.first.id;
      await backend.addToLibrary(manga);

      await backend.setMangaCategories(manga, {catA.id, catB.id});
      expect(await backend.getMangaCategoryIds(manga), {catA.id, catB.id});
      expect((await backend.getCategoryManga(catA.id)).map((m) => m.id),
          contains(manga));
      final counted =
          (await backend.getCategories()).firstWhere((c) => c.id == catA.id);
      expect(counted.mangaCount, 1);

      await backend.setMangaCategories(manga, {catB.id});
      expect(await backend.getMangaCategoryIds(manga), {catB.id});
      expect((await backend.getCategoryManga(catA.id)).map((m) => m.id),
          isNot(contains(manga)));

      final chapters = await backend.getChapters(manga);
      expect(chapters, isNotEmpty);
      expect(chapters.first.bookmarked, isFalse);
      await backend.setChapterBookmarked(chapters.first.id, true);
      expect(
          (await backend.getChapters(manga))
              .firstWhere((c) => c.id == chapters.first.id)
              .bookmarked,
          isTrue);
      await backend.setChapterBookmarked(chapters.first.id, false);

      await backend.deleteCategory(catA.id);
      await backend.deleteCategory(catB.id);
      all = await backend.getCategories();
      expect(all.map((c) => c.id), isNot(contains(catA.id)));
      // Deleting a category leaves the manga in the library, under Default.
      expect((await backend.getMangaCategoryIds(manga)), isEmpty);
      expect((await backend.getMangaDetail(manga)).inLibrary, isTrue);
      await backend.removeFromLibrary(manga);
    }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Komga collections', () {
    final url = env['KAI_KOMGA_URL'];
    final email = env['KAI_KOMGA_EMAIL'];
    final password = env['KAI_KOMGA_PASSWORD'];
    final skip = (url == null || email == null || password == null)
        ? 'KAI_KOMGA_* not set'
        : null;
    late KomgaBackend backend;
    final a = 'It A $stamp';
    final b = 'It B $stamp';

    setUpAll(() async {
      if (skip != null) return;
      backend = KomgaBackend(info(url!, BackendType.komga));
      final auth = await backend
          .login(KomgaPasswordCredentials(email: email!, password: password!));
      expect(auth.success, isTrue);
    });
    tearDownAll(() async {
      if (skip == null) await removeAll(backend, [a, b, '$a renamed']);
    });

    test('create, rename, assign, remove, delete', () async {
      expect(backend.canCreateEmptyCategory, isFalse);
      await expectLater(
          backend.createCategory(a), throwsA(isA<BackendException>()));

      final series = (await backend.getMangaList()).take(2).toList();
      expect(series.length, 2);
      final s1 = series[0].id, s2 = series[1].id;

      final catA = await backend.createCategory(a, firstMangaId: s1);
      expect(catA.mangaCount, 1);
      expect(await backend.getMangaCategoryIds(s1), {catA.id});

      await backend.renameCategory(catA.id, '$a renamed');
      expect((await backend.getCategories()).map((c) => c.name),
          contains('$a renamed'));

      // Several collections per series, and several series per collection.
      final catB = await backend.createCategory(b, firstMangaId: s1);
      await backend.setMangaCategories(s2, {catA.id});
      expect(await backend.getMangaCategoryIds(s1), {catA.id, catB.id});
      expect((await backend.getCategoryManga(catA.id)).map((m) => m.id),
          unorderedEquals([s1, s2]));

      await backend.setMangaCategories(s1, {catA.id});
      expect(await backend.getMangaCategoryIds(s1), {catA.id});
      expect((await backend.getCategoryManga(catA.id)).length, 2);

      // Komga forbids an empty collection, so emptying one removes it.
      await backend.setMangaCategories(s2, {});
      await backend.setMangaCategories(s1, {});
      expect((await backend.getCategories()).map((c) => c.id),
          isNot(contains(catA.id)));

      // Taking s1 out of B earlier already emptied it, hence removed it.
      expect((await backend.getCategories()).map((c) => c.id),
          isNot(contains(catB.id)));

      // Explicit delete of a non-empty collection.
      final catC = await backend.createCategory(b, firstMangaId: s2);
      await backend.deleteCategory(catC.id);
      expect((await backend.getCategories()).map((c) => c.id),
          isNot(contains(catC.id)));
    }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Kavita collections', () {
    final url = env['KAI_KAVITA_URL'];
    final apiKey = env['KAI_KAVITA_API_KEY'];
    final skip =
        (url == null || apiKey == null) ? 'KAI_KAVITA_* not set' : null;
    late KavitaBackend backend;
    final a = 'It A $stamp';
    final b = 'It B $stamp';

    setUpAll(() async {
      if (skip != null) return;
      backend = KavitaBackend(info(url!, BackendType.kavita));
      expect((await backend.login(KavitaCredentials(apiKey: apiKey!))).success,
          isTrue);
    });
    tearDownAll(() async {
      if (skip == null) await removeAll(backend, [a, b, '$a renamed']);
    });

    test('create, rename, assign, remove, delete', () async {
      final series = (await backend.getMangaList()).take(2).toList();
      expect(series.length, 2);
      final s1 = series[0].id, s2 = series[1].id;

      final empty = await backend.createCategory(a);
      expect(empty.mangaCount, 0);
      await backend.renameCategory(empty.id, '$a renamed');
      expect((await backend.getCategories()).map((c) => c.name),
          contains('$a renamed'));

      final catB = await backend.createCategory(b, firstMangaId: s1);
      expect(catB.mangaCount, 1);

      await backend.setMangaCategories(s1, {empty.id, catB.id});
      await backend.setMangaCategories(s2, {empty.id});
      expect(await backend.getMangaCategoryIds(s1), {empty.id, catB.id});
      expect((await backend.getCategoryManga(empty.id)).map((m) => m.id),
          unorderedEquals([s1, s2]));
      expect(
          (await backend.getCategories())
              .firstWhere((c) => c.id == empty.id)
              .mangaCount,
          2);

      await backend.setMangaCategories(s1, {catB.id});
      expect((await backend.getCategoryManga(empty.id)).map((m) => m.id), [s2]);

      await backend.deleteCategory(empty.id);
      await backend.deleteCategory(catB.id);
      final left = (await backend.getCategories()).map((c) => c.id);
      expect(left, isNot(contains(empty.id)));
      expect(left, isNot(contains(catB.id)));
    }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
  });
}
