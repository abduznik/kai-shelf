@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kai_shelf/core/backend/auth_credentials.dart';
import 'package:kai_shelf/core/backend/detector/backend_detector.dart';
import 'package:kai_shelf/core/backend/kavita/kavita_backend.dart';
import 'package:kai_shelf/core/backend/models.dart';

/// Runs the Kavita adapter against a real server. Skipped unless
/// KAI_KAVITA_URL and KAI_KAVITA_API_KEY are set. The server needs a
/// series named "Alpha Saga" with three 4-page chapters.
void main() {
  final env = Platform.environment;
  final url = env['KAI_KAVITA_URL'];
  final apiKey = env['KAI_KAVITA_API_KEY'];
  final skip = (url == null || apiKey == null) ? 'KAI_KAVITA_* not set' : null;

  late KavitaBackend backend;

  setUpAll(() async {
    if (skip != null) return;
    backend = KavitaBackend(ServerConnectionInfo(
      serverId: 'live',
      displayName: 'live',
      baseUrl: Uri.parse(url!),
      type: BackendType.kavita,
    ));
    final auth = await backend.login(KavitaCredentials(apiKey: apiKey!));
    expect(auth.success, isTrue, reason: auth.error);
  });

  test('detects Kavita', () async {
    final detector = BackendDetector();
    final result = await detector.detect(url!);
    detector.dispose();
    expect(result?.type, BackendType.kavita);
  }, skip: skip);

  test('rejects a wrong API key', () async {
    final other = KavitaBackend(backend.connectionInfo);
    final r = await other.login(const KavitaCredentials(apiKey: 'nope'));
    expect(r.success, isFalse);
  }, skip: skip);

  test('lists libraries and series, with search', () async {
    expect(await backend.getLibraries(), isNotEmpty);
    final all = await backend.getAllManga();
    expect(all.map((m) => m.title), containsAll(['Alpha Saga', 'Beta Quest']));
    final found = await backend.getAllManga(searchQuery: 'Alpha');
    expect(found.map((m) => m.title), contains('Alpha Saga'));
  }, skip: skip);

  test('chapters, pages, covers and read progress', () async {
    final series = (await backend.getAllManga(searchQuery: 'Alpha')).first;
    final detail = await backend.getMangaDetail(series.id);
    expect(detail.title, 'Alpha Saga');

    final chapters = await backend.getChapters(series.id);
    expect(chapters.length, 3);

    final pages = await backend.getPages(chapters.first.id);
    expect(pages.length, 4);
    final image = await http.get(Uri.parse(pages.first.imageUrl),
        headers: pages.first.extraHeaders);
    expect(image.statusCode, 200);
    expect(image.headers['content-type'], startsWith('image/'));

    final cover = await http.get(Uri.parse(series.coverUrl!),
        headers: series.coverHeaders);
    expect(cover.statusCode, 200);

    await backend.updateReadProgress(chapters.first.id, read: true);
    final after = (await backend.getChapters(series.id)).first;
    expect(after.read, isTrue);
  }, skip: skip);

  test('reader works without listing the series first (deep link)', () async {
    final series = (await backend.getAllManga(searchQuery: 'Beta')).first;
    final chapters = await backend.getChapters(series.id);
    final id = chapters.last.id;

    final fresh = KavitaBackend(backend.connectionInfo);
    final pages = await fresh.getPages(id);
    expect(pages.length, 4);
    await fresh.updateReadProgress(id, read: false, lastPageRead: 1);
  }, skip: skip);

  test('volume-only series get readable titles in volume order', () async {
    final series = (await backend.getAllManga(searchQuery: 'Alpha')).first;
    final titles = (await backend.getChapters(series.id)).map((c) => c.title);
    expect(titles, everyElement(startsWith('Volume ')));
    expect(titles.toSet().length, 3);
  }, skip: skip);

  test('history lists read chapters newest first', () async {
    final series = (await backend.getAllManga(searchQuery: 'Beta')).first;
    final chapters = await backend.getChapters(series.id);
    expect(chapters.length, 3);

    await backend.updateReadProgress(chapters[0].id,
        read: false, lastPageRead: 1);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await backend.updateReadProgress(chapters[1].id,
        read: false, lastPageRead: 2);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await backend.updateReadProgress(chapters[2].id, read: true);

    // Other live tests share this server and read chapters too, so look at
    // this test's own series only.
    final everything = await backend.getHistory(limit: 50);
    final history = everything.where((e) => e.mangaId == series.id).toList();
    expect(history.take(3).map((e) => e.chapterId),
        [chapters[2].id, chapters[1].id, chapters[0].id]);
    final top = history.first;
    expect(top.read, isTrue);
    expect(top.mangaId, series.id);
    expect(top.mangaTitle, series.title);
    expect(top.chapterTitle, startsWith('Volume '));
    expect(top.pageCount, 4);
    expect(history[1].read, isFalse);
    expect(history[1].lastPageRead, 2);

    final cover =
        await http.get(Uri.parse(top.coverUrl!), headers: top.coverHeaders);
    expect(cover.statusCode, 200);

    final second = await backend.getHistory(limit: 2, offset: 2);
    expect(second.first.chapterId, everything[2].chapterId);
  }, skip: skip);
}
