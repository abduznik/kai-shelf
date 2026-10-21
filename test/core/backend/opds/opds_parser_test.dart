import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/opds/opds_models.dart';
import 'package:kai_shelf/core/backend/opds/opds_parser.dart';

import 'opds_fixtures.dart';

void main() {
  final rootUrl = Uri.parse('$opdsBaseOrigin/opds/root.xml');

  group('parseOpdsCatalog', () {
    test('parses a navigation root into its sub-catalogs and search facet', () {
      final feed = parseOpdsCatalog(navRootFeedXml, feedUrl: rootUrl);

      expect(feed.title, 'Test Catalog Root');
      expect(feed.selfHref, Uri.parse('$opdsBaseOrigin/opds/root.xml'));
      expect(feed.startHref, Uri.parse('$opdsBaseOrigin/opds/root.xml'));
      expect(feed.searchLink?.href,
          Uri.parse('$opdsBaseOrigin/opds/opensearch.xml'));
      expect(feed.searchLink?.isOpdsSearchFacet, isTrue);

      // Both spec shapes: a http://opds-spec.org/sort/... entry link and a
      // plain subsection link, each with a relative href resolved against
      // the feed's own URL.
      final children = feed.subCatalogLinks;
      expect(children, hasLength(2));
      expect(children[0].rel, 'http://opds-spec.org/sort/popular');
      expect(children[0].href, Uri.parse('$opdsBaseOrigin/opds/popular.xml'));
      expect(children[1].rel, 'subsection');
      expect(children[1].href, Uri.parse('$opdsBaseOrigin/opds/all.xml'));
    });

    test('parses acquisition entries: titles, authors, covers, formats', () {
      final feed = parseOpdsCatalog(acquisitionFeedXml, feedUrl: rootUrl);

      expect(feed.title, 'All Books');
      expect(feed.entries, hasLength(2));

      final first = feed.entries[0];
      // The Office of the Historian quirk: the atom id arrives as an
      // xml:id attribute on an empty <id/> element.
      expect(first.id, 'bob-son-of-bob');
      expect(first.title, 'Bob, Son of Bob');
      expect(first.authors, ['Bob the Recursive']);
      expect(first.summary, contains('son of Bob'));
      expect(first.categories, ["FICTION / Men's Adventure"]);
      expect(first.updated, isNotNull);

      // Full-size cover preferred over the thumbnail, both absolute.
      expect(
          first.coverLink?.href, Uri.parse('$opdsBaseOrigin/covers/bob.png'));
      expect(first.coverLink?.isCover, isTrue);

      final formats = first.acquisitionLinks;
      expect(formats, hasLength(2));
      expect(formats[0].href, Uri.parse('$opdsBaseOrigin/content/bob.epub'));
      expect(formats[0].type, 'application/epub+zip');
      expect(formats[1].title, 'Mobipocket');
      // The alternate link points at an Atom *entry* document, not another
      // catalog feed, so it must not be browsable as a sub-catalog.
      expect(first.subCatalogLinks, isEmpty);

      // The open-access variant counts as an acquisition too, and a
      // cross-origin absolute href is kept as-is.
      final second = feed.entries[1];
      expect(second.acquisitionLinks.single.href,
          Uri.parse('https://cdn.example/second.pdf'));
      expect(second.acquisitionLinks.single.isAcquisition, isTrue);
    });

    test('exposes rel="next" paging links', () {
      final feed = parseOpdsCatalog(acquisitionFeedXml, feedUrl: rootUrl);
      expect(feed.nextHref, Uri.parse('$opdsBaseOrigin/opds/all.xml?page=2'));

      final last = parseOpdsCatalog(acquisitionFeedPage2Xml,
          feedUrl: Uri.parse('$opdsBaseOrigin/opds/all.xml?page=2'));
      expect(last.nextHref, isNull);
      expect(last.entries.single.title, 'Third Book');
    });

    test('a navigation feed with no book entries reports none', () {
      final feed = parseOpdsCatalog(navRootFeedXml, feedUrl: rootUrl);
      expect(feed.hasBookEntries, isFalse);
      final books = parseOpdsCatalog(acquisitionFeedXml, feedUrl: rootUrl);
      expect(books.hasBookEntries, isTrue);
    });

    test('rejects malformed XML with a FormatException', () {
      expect(() => parseOpdsCatalog(malformedFeedXml, feedUrl: rootUrl),
          throwsFormatException);
    });

    test('rejects well-formed XML that is not an Atom feed', () {
      expect(() => parseOpdsCatalog(sitemapXml, feedUrl: rootUrl),
          throwsFormatException);
      expect(() => parseOpdsCatalog(htmlPage, feedUrl: rootUrl),
          throwsFormatException);
    });
  });

  group('looksLikeOpdsCatalog', () {
    test('accepts both navigation and acquisition feeds', () {
      expect(looksLikeOpdsCatalog(navRootFeedXml), isTrue);
      expect(looksLikeOpdsCatalog(acquisitionFeedXml), isTrue);
      expect(looksLikeOpdsCatalog(searchResultsFeedXml), isTrue);
    });

    test('rejects malformed XML, HTML and non-catalog XML', () {
      expect(looksLikeOpdsCatalog(malformedFeedXml), isFalse);
      expect(looksLikeOpdsCatalog(htmlPage), isFalse);
      expect(looksLikeOpdsCatalog(sitemapXml), isFalse);
      expect(looksLikeOpdsCatalog(''), isFalse);
    });

    test('rejects an Atom feed without OPDS catalog relations', () {
      expect(looksLikeOpdsCatalog(blogAtomFeedXml), isFalse);
    });
  });

  group('parseOpensearchAtomTemplate', () {
    test('picks the Atom template over an earlier HTML one', () {
      expect(
        parseOpensearchAtomTemplate(openSearchDescriptionXml),
        'https://library.example/api/v1/catalog/search?q={searchTerms}',
      );
    });

    test('returns null for a description with no Atom Url', () {
      const htmlOnly = '<OpenSearchDescription '
          'xmlns="http://a9.com/-/spec/opensearch/1.1/">'
          '<Url type="text/html" template="https://x.example/?q={searchTerms}"/>'
          '</OpenSearchDescription>';
      expect(parseOpensearchAtomTemplate(htmlOnly), isNull);
      expect(parseOpensearchAtomTemplate(malformedFeedXml), isNull);
    });
  });

  group('OpdsLink classification', () {
    test('only genuine catalog-feed links count as sub-catalogs', () {
      final link = OpdsLink(
        rel: 'subsection',
        href: Uri.parse('https://library.example/opds/all.xml'),
        type: 'application/atom+xml;profile=opds-catalog;kind=acquisition',
      );
      expect(link.isSubCatalogFeed, isTrue);
      final acquisition = OpdsLink(
        rel: 'http://opds-spec.org/acquisition',
        href: Uri.parse('https://library.example/a.epub'),
        type: 'application/epub+zip',
      );
      expect(acquisition.isSubCatalogFeed, isFalse);
      expect(acquisition.isAcquisition, isTrue);
    });
  });
}
