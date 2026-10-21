/// Canned OPDS 1.2 Atom XML for unit tests.
///
/// Shapes follow the OPDS 1.2 spec's own examples plus the two quirks
/// confirmed against real public catalogs (the Office of the Historian ebook
/// catalog, https://history.state.gov/api/v1/catalog):
///  * the catalog answers `text/xml`, not `application/atom+xml`, so nothing
///    may key off the content type;
///  * entry ids can arrive as an `xml:id` attribute instead of element text.
const String opdsBaseOrigin = 'https://library.example';

/// A navigation-style catalog root: sub-catalogs as entries, with relative
/// hrefs, an OpenSearch description search facet and feed-level self/start
/// links, mirroring the OPDS 1.2 spec's root example.
const String navRootFeedXml = r'''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>urn:uuid:2853dacf-ed79-42f5-8e8a-a7bb3d1ae6a2</id>
  <title>Test Catalog Root</title>
  <updated>2026-01-10T10:03:10Z</updated>
  <link rel="self" href="/opds/root.xml" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  <link rel="start" href="/opds/root.xml" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  <link rel="search" href="/opds/opensearch.xml" type="application/opensearchdescription+xml" title="Search the catalog"/>
  <entry>
    <title>Popular Publications</title>
    <link rel="http://opds-spec.org/sort/popular" href="/opds/popular.xml" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
    <updated>2026-01-10T10:01:01Z</updated>
    <id>urn:uuid:d49e8018-a0e0-499e-9423-7c175fa0c56e</id>
    <content type="text">Popular publications from this catalog based on downloads.</content>
  </entry>
  <entry>
    <title>All Books</title>
    <link rel="subsection" href="/opds/all.xml" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
    <updated>2026-01-10T10:02:00Z</updated>
    <id>urn:uuid:d49e8018-a0e0-499e-9423-7c175fa0c56c</id>
    <content type="text">Every book in the catalog.</content>
  </entry>
</feed>
''';

/// An acquisition feed: two publications, covers, authors, summaries, two
/// formats for the first entry, `rel="next"` paging, and an entry id given
/// as an `xml:id` attribute (as the Office of the Historian catalog does).
const String acquisitionFeedXml = r'''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/terms/">
  <id>https://library.example/opds/all.xml</id>
  <title>All Books</title>
  <updated>2026-01-11T09:00:00Z</updated>
  <link rel="self" href="/opds/all.xml" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  <link rel="next" href="/opds/all.xml?page=2" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  <link rel="search" href="/opds/opensearch.xml" type="application/opensearchdescription+xml"/>
  <entry>
    <title>Bob, Son of Bob</title>
    <id xml:id="bob-son-of-bob"/>
    <updated>2026-01-11T09:00:00Z</updated>
    <author>
      <name>Bob the Recursive</name>
      <uri>https://library.example/authors/1285</uri>
    </author>
    <dc:language>en</dc:language>
    <category term="FIC020000" label="FICTION / Men's Adventure"/>
    <summary type="text">The story of the son of Bob and the part he played.</summary>
    <link rel="http://opds-spec.org/image" href="/covers/bob.png" type="image/png"/>
    <link rel="http://opds-spec.org/image/thumbnail" href="/covers/bob.thumb.png" type="image/png"/>
    <link rel="alternate" href="/entries/bob.complete.xml" type="application/atom+xml;type=entry;profile=opds-catalog" title="Complete Catalog Entry"/>
    <link rel="http://opds-spec.org/acquisition" href="/content/bob.epub" type="application/epub+zip"/>
    <link rel="http://opds-spec.org/acquisition" href="/content/bob.mobi" type="application/x-mobipocket-ebook" title="Mobipocket"/>
  </entry>
  <entry>
    <title>Second Book</title>
    <id>urn:uuid:0cf7f00d-0000-4000-8000-000000000002</id>
    <updated>2026-01-10T08:00:00Z</updated>
    <author>
      <name>Jane Doe</name>
    </author>
    <summary type="text">A tale of two cities and one repository.</summary>
    <link rel="http://opds-spec.org/acquisition/open-access" href="https://cdn.example/second.pdf" type="application/pdf"/>
  </entry>
</feed>
''';

/// Second page of [acquisitionFeedXml], reached via its `rel="next"` link.
const String acquisitionFeedPage2Xml =
    r'''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>https://library.example/opds/all.xml?page=2</id>
  <title>All Books (page 2)</title>
  <link rel="self" href="/opds/all.xml?page=2" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  <entry>
    <title>Third Book</title>
    <id>urn:uuid:0cf7f00d-0000-4000-8000-000000000003</id>
    <updated>2026-01-09T08:00:00Z</updated>
    <summary type="text">The sequel nobody asked for.</summary>
    <link rel="http://opds-spec.org/acquisition" href="/content/third.epub" type="application/epub+zip"/>
  </entry>
</feed>
''';

/// A search result feed in the shape the Office of the Historian catalog
/// actually returns: the hit is a *navigation* entry pointing at a
/// sub-catalog, not a book directly.
const String searchResultsFeedXml = r'''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="en">
  <id>https://library.example/api/v1/catalog/search?q=nixon%20papers</id>
  <title>Search ebooks for "nixon papers"</title>
  <link type="application/atom+xml;profile=opds-catalog;kind=acquisition" rel="self" href="https://library.example/api/v1/catalog/search?q=nixon%20papers"/>
  <link type="application/opensearchdescription+xml" rel="search" href="https://library.example/opensearch.xml" title="Search the catalog"/>
  <entry>
    <title>Nixon, Richard</title>
    <id>nixon-richard</id>
    <updated>2026-01-11T09:00:00Z</updated>
    <summary type="text">2 volumes</summary>
    <link type="application/atom+xml;profile=opds-catalog;kind=navigation" rel="subsection" href="https://library.example/opds/browse?tag=nixon-richard"/>
  </entry>
</feed>
''';

/// What the `rel="subsection"` hit in [searchResultsFeedXml] resolves to.
const String searchHitChildrenFeedXml =
    r'''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>https://library.example/opds/browse?tag=nixon-richard</id>
  <title>Nixon, Richard</title>
  <entry>
    <title>Nixon Papers 1969</title>
    <id>urn:uuid:nixon-1969</id>
    <author><name>Richard Nixon</name></author>
    <link rel="http://opds-spec.org/acquisition" href="/content/nixon-1969.epub" type="application/epub+zip"/>
  </entry>
  <entry>
    <title>Nixon Papers 1972</title>
    <id>urn:uuid:nixon-1972</id>
    <author><name>Richard Nixon</name></author>
    <link rel="http://opds-spec.org/acquisition" href="/content/nixon-1972.epub" type="application/epub+zip"/>
  </entry>
</feed>
''';

/// An OpenSearch description document, with the HTML Url listed *before* the
/// Atom one — the parser must pick the Atom template, not the first Url.
const String openSearchDescriptionXml =
    r'''<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
    <ShortName>Test Catalog</ShortName>
    <Description>Search the catalog</Description>
    <InputEncoding>UTF-8</InputEncoding>
    <Url type="text/html" template="https://library.example/search?q={searchTerms}"/>
    <Url type="application/atom+xml" template="https://library.example/api/v1/catalog/search?q={searchTerms}"/>
    <Query role="example" searchTerms="example"/>
</OpenSearchDescription>''';

/// A catalog that advertises its search facet as a templated href directly
/// (no OpenSearch description hop), like Calibre-Web does.
const String templatedSearchFeedXml = r'''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>https://library.example/opds/root.xml</id>
  <title>Templated Search Catalog</title>
  <link rel="self" href="/opds/root.xml" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  <link rel="search" href="/opds/search/{searchTerms}" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  <entry>
    <title>All Books</title>
    <id>urn:uuid:templated-all</id>
    <link rel="subsection" href="/opds/all.xml" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  </entry>
</feed>
''';

/// A catalog whose search link has neither a template nor an OpenSearch
/// description — the fallback appends `?q=` instead.
const String untemplatedSearchFeedXml =
    r'''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>https://library.example/opds/root.xml</id>
  <title>Untemplated Search Catalog</title>
  <link rel="search" href="https://library.example/opds/search" type="application/atom+xml"/>
  <entry>
    <title>All Books</title>
    <id>urn:uuid:untemplated-all</id>
    <link rel="subsection" href="/opds/all.xml" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  </entry>
</feed>
''';

/// The navigation root without any `rel="search"` facet, for catalogs that
/// cannot be searched at all.
const String navRootFeedNoSearchXml = r'''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>urn:uuid:2853dacf-ed79-42f5-8e8a-a7bb3d1ae6a3</id>
  <title>Unsearchable Catalog Root</title>
  <link rel="self" href="/opds/root.xml" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  <entry>
    <title>All Books</title>
    <link rel="subsection" href="/opds/all.xml" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
    <id>urn:uuid:d49e8018-a0e0-499e-9423-7c175fa0c56d</id>
  </entry>
</feed>
''';

/// Truncated mid-element — not well-formed XML.
const String malformedFeedXml =
    '<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Oops';

/// Well-formed XML, but an Atom feed with no OPDS relations at all — a blog
/// feed must never be detected as an OPDS catalog.
const String blogAtomFeedXml = r'''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>A Blog</title>
  <link rel="self" href="https://blog.example/atom.xml" type="application/atom+xml"/>
  <link rel="alternate" href="https://blog.example/" type="text/html"/>
  <entry>
    <title>Hello</title>
    <id>tag:blog.example,2026:1</id>
    <link rel="alternate" href="https://blog.example/hello" type="text/html"/>
  </entry>
</feed>
''';

/// A sitemap: XML with a `<urlset>` root — not an Atom feed.
const String sitemapXml = r'''<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://library.example/</loc></url>
</urlset>
''';

/// An ordinary HTML page, e.g. what Komga/Kavita/Suwayomi serve at `/`.
const String htmlPage =
    '<!DOCTYPE html><html><head><title>Komga</title></head><body>hi</body></html>';
