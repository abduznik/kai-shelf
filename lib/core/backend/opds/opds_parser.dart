/// OPDS 1.2 parsing, kept free of I/O so it can be exercised against canned
/// fixtures. See https://specs.opds.io/opds-1.2.html for the document model.
library;

import 'package:xml/xml.dart';

import 'opds_models.dart';

const String atomNamespace = 'http://www.w3.org/2005/Atom';
const String xmlIdNamespace = 'http://www.w3.org/XML/1998/namespace';

/// Parses an OPDS catalog feed document ([feedUrl] is used to resolve the
/// relative hrefs catalogs love to use).
///
/// Throws [FormatException] when [xmlString] is not a well-formed Atom feed
/// document — callers treat that as "this is not an OPDS catalog".
OpdsFeed parseOpdsCatalog(String xmlString, {required Uri feedUrl}) {
  final document = _parseDocument(xmlString);
  final root = document.rootElement;
  if (!_isAtomFeed(root)) {
    throw const FormatException('Not an Atom feed document.');
  }
  return OpdsFeed(
    title: _childText(root, 'title') ?? '',
    links: _parseLinks(root, feedUrl),
    entries: [
      for (final element in _childElements(root, 'entry'))
        _parseEntry(element, feedUrl),
    ],
  );
}

/// Cheap "is this actually an OPDS catalog?" test for auto-detection.
///
/// Reads the document rather than trusting the content type — the Office of
/// the Historian catalog answers `text/xml` — and requires both an Atom feed
/// document and at least one link carrying an OPDS relation or an
/// `opds-catalog` media type, so an Atom blog feed, a sitemap or a server's
/// HTML error page can never match.
bool looksLikeOpdsCatalog(String body) {
  final XmlDocument? document = _tryParseDocument(body);
  if (document == null) return false;
  if (!_isAtomFeed(document.rootElement)) return false;
  for (final element in document.descendants.whereType<XmlElement>()) {
    if (element.name.local != 'link') continue;
    final rel = (element.getAttribute('rel') ?? '').toLowerCase();
    final type = (element.getAttribute('type') ?? '').toLowerCase();
    if (type.contains('opds-catalog')) return true;
    if (rel.startsWith('http://opds-spec.org/')) return true;
  }
  return false;
}

/// Extracts the Atom search template from an OpenSearch description
/// document, e.g. `.../catalog/search?q={searchTerms}`.
///
/// Returns null when the description has no Atom-capable `Url` — falling
/// back to an HTML template would send the user's query to a web page
/// instead of a feed.
String? parseOpensearchAtomTemplate(String xmlString) {
  final XmlDocument? document = _tryParseDocument(xmlString);
  if (document == null) return null;
  for (final element in document.descendants.whereType<XmlElement>()) {
    if (element.name.local.toLowerCase() != 'url') continue;
    final type = (element.getAttribute('type') ?? '').toLowerCase();
    if (!type.contains('atom')) continue;
    final template = element.getAttribute('template');
    if (template != null && template.isNotEmpty) return template;
  }
  return null;
}

XmlDocument? _tryParseDocument(String xmlString) {
  try {
    return XmlDocument.parse(xmlString);
  } on XmlException {
    return null;
  }
}

XmlDocument _parseDocument(String xmlString) {
  final document = _tryParseDocument(xmlString);
  if (document == null) {
    throw const FormatException('Could not parse the response as XML.');
  }
  return document;
}

bool _isAtomFeed(XmlElement root) =>
    root.name.local == 'feed' && root.name.namespaceUri == atomNamespace;

Iterable<XmlElement> _childElements(XmlElement parent, String localName) =>
    parent.childElements.where((element) => element.name.local == localName);

String? _childText(XmlElement parent, String localName) {
  for (final element in _childElements(parent, localName)) {
    final text = element.innerText.trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

List<OpdsLink> _parseLinks(XmlElement parent, Uri feedUrl) => [
      for (final element in _childElements(parent, 'link'))
        OpdsLink(
          rel: element.getAttribute('rel') ?? '',
          href: feedUrl.resolve(element.getAttribute('href') ?? ''),
          type: element.getAttribute('type'),
          title: element.getAttribute('title'),
        ),
    ];

OpdsEntry _parseEntry(XmlElement element, Uri feedUrl) {
  var id = _childText(element, 'id') ?? '';
  if (id.isEmpty) {
    // The Office of the Historian catalog ships `<id xml:id="frus1861"/>`:
    // an empty element carrying the id as an xml:id attribute. package:xml
    // leaves the `xml` prefix's namespace URI unbound on attributes
    // (name.namespaceUri is null), so match on the prefix itself.
    for (final idElement in _childElements(element, 'id')) {
      id = _xmlId(idElement) ?? '';
      if (id.isNotEmpty) break;
    }
  }
  final authors = <String>[];
  for (final author in _childElements(element, 'author')) {
    final name = _childText(author, 'name');
    if (name != null) authors.add(name);
  }
  final categories = <String>[];
  for (final category in _childElements(element, 'category')) {
    final label =
        (category.getAttribute('label') ?? category.getAttribute('term') ?? '')
            .trim();
    if (label.isNotEmpty) categories.add(label);
  }
  return OpdsEntry(
    id: id,
    title: _childText(element, 'title') ?? '',
    authors: authors,
    summary: _childText(element, 'summary') ?? _childText(element, 'content'),
    categories: categories,
    links: _parseLinks(element, feedUrl),
    updated: DateTime.tryParse(_childText(element, 'updated') ?? ''),
  );
}

/// The value of an `xml:id` attribute on [element], if it has one.
String? _xmlId(XmlElement element) {
  for (final attribute in element.attributes) {
    if (attribute.name.local != 'id') continue;
    if (attribute.name.prefix == 'xml' ||
        attribute.name.namespaceUri == xmlIdNamespace) {
      final value = attribute.value.trim();
      if (value.isNotEmpty) return value;
    }
  }
  return null;
}
