import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/opds/opds_ids.dart';

void main() {
  group('entry ids', () {
    test('round-trip a feed URL and entry key', () {
      const feedUrl = 'https://library.example/opds/all.xml?page=2';
      const entryKey = 'bob-son-of-bob';

      final id = encodeOpdsEntryRef(feedUrl: feedUrl, entryKey: entryKey);
      final decoded = decodeOpdsEntryRef(id);

      expect(decoded.feedUrl, feedUrl);
      expect(decoded.entryKey, entryKey);
    });

    test('encoded ids are safe in a route path and a folder name', () {
      // Ids end up in '/manga/:mangaId' and '/reader/:mangaId/:chapterId'
      // route segments and in on-disk download folder names, so they may
      // not contain '/', '%', spaces or query characters.
      final id = encodeOpdsEntryRef(
        feedUrl: 'https://library.example/opds/all.xml?q=a b&x=1',
        entryKey: 'urn:uuid:6409a00b-7bf2-405e-826c-3fdff0fd0734',
      );
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id), isTrue);
    });

    test('rejects an id that was not produced by the encoder', () {
      expect(
          () => decodeOpdsEntryRef('!!! not an id !!!'), throwsFormatException);
    });
  });

  group('acquisition ids', () {
    test('round-trip an acquisition URL', () {
      const url = 'https://library.example/content/bob.epub?v=1&a=2';
      final id = encodeOpdsAcquisition(url);
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id), isTrue);
      expect(decodeOpdsAcquisition(id).toString(), url);
    });

    test('rejects garbage', () {
      expect(() => decodeOpdsAcquisition('!!'), throwsFormatException);
    });
  });
}
