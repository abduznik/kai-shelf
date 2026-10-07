@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kai_shelf/core/backend/auth_credentials.dart';
import 'package:kai_shelf/core/backend/detector/backend_detector.dart';
import 'package:kai_shelf/core/backend/komga/komga_backend.dart';
import 'package:kai_shelf/core/backend/models.dart';

/// Runs the Komga adapter against a real server. Skipped unless
/// KAI_KOMGA_URL, KAI_KOMGA_EMAIL and KAI_KOMGA_PASSWORD are set. The
/// server needs at least one library of more than 200 series (to prove
/// listing isn't truncated to a single page) and a series with chapters.
void main() {
  final env = Platform.environment;
  final url = env['KAI_KOMGA_URL'];
  final email = env['KAI_KOMGA_EMAIL'];
  final password = env['KAI_KOMGA_PASSWORD'];
  final skip = (url == null || email == null || password == null)
      ? 'KAI_KOMGA_* not set'
      : null;

  late KomgaBackend backend;

  setUpAll(() async {
    if (skip != null) return;
    backend = KomgaBackend(ServerConnectionInfo(
      serverId: 'live',
      displayName: 'live',
      baseUrl: Uri.parse(url!),
      type: BackendType.komga,
    ));
    final auth = await backend
        .login(KomgaPasswordCredentials(email: email!, password: password!));
    expect(auth.success, isTrue, reason: auth.error);
  });

  test('detects Komga', () async {
    final detector = BackendDetector();
    final result = await detector.detect(url!);
    detector.dispose();
    expect(result?.type, BackendType.komga);
  }, skip: skip);

  test('rejects a wrong password', () async {
    final other = KomgaBackend(backend.connectionInfo);
    final r = await other
        .login(KomgaPasswordCredentials(email: email!, password: 'nope'));
    expect(r.success, isFalse);
  }, skip: skip);

  test('lists libraries and every series, not just the first page', () async {
    final libraries = await backend.getLibraries();
    expect(libraries, isNotEmpty);

    final all = await backend.getAllManga();
    final firstPage = await backend.getMangaList();
    expect(all.length, greaterThan(200));
    expect(all.length, greaterThan(firstPage.length));
    expect(all.map((m) => m.id).toSet().length, all.length);

    final search = await backend.getAllManga(searchQuery: 'Alpha');
    expect(search.map((m) => m.title), contains('Alpha Saga'));
  }, skip: skip);

  test('chapters, pages, covers, downloads and progress', () async {
    final series = (await backend.getAllManga(searchQuery: 'Alpha')).first;
    final detail = await backend.getMangaDetail(series.id);
    expect(detail.title, series.title);

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

    await backend.updateReadProgress(chapters.first.id,
        read: false, lastPageRead: 2);
    var after = (await backend.getChapters(series.id)).first;
    expect(after.lastPageRead, 2);
    await backend.updateReadProgress(chapters.first.id, read: true);
    after = (await backend.getChapters(series.id)).first;
    expect(after.read, isTrue);
  }, skip: skip);

  test('history lists read chapters newest first', () async {
    final series = (await backend.getAllManga(searchQuery: 'Beta')).first;
    final chapters = await backend.getChapters(series.id);
    expect(chapters.length, 3);

    // Komga stamps progress with one-second resolution, so space the reads.
    await backend.updateReadProgress(chapters[0].id,
        read: false, lastPageRead: 1);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await backend.updateReadProgress(chapters[1].id,
        read: false, lastPageRead: 2);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await backend.updateReadProgress(chapters[2].id, read: true);

    final history = await backend.getHistory(limit: 20);
    expect(history.take(3).map((e) => e.chapterId),
        [chapters[2].id, chapters[1].id, chapters[0].id]);
    final top = history.first;
    expect(top.read, isTrue);
    expect(top.mangaId, series.id);
    expect(top.mangaTitle, series.title);
    expect(top.pageCount, 4);
    expect(history[1].read, isFalse);
    expect(history[1].lastPageRead, 2);
    expect(history[0].lastReadAt.isAfter(history[1].lastReadAt), isTrue);

    final cover =
        await http.get(Uri.parse(top.coverUrl!), headers: top.coverHeaders);
    expect(cover.statusCode, 200);

    // Paging: the second page starts where the first ended.
    final first = await backend.getHistory(limit: 2);
    final second = await backend.getHistory(limit: 2, offset: 2);
    expect(
        first.map((e) => e.chapterId), history.take(2).map((e) => e.chapterId));
    expect(second.first.chapterId, history[2].chapterId);
  }, skip: skip);
}
