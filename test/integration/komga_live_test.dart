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
}
