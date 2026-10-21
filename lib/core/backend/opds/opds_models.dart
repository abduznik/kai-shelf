/// Relation values defined by the OPDS 1.2 catalog specification.
const String opdsAcquisitionRelation = 'http://opds-spec.org/acquisition';
const String opdsImageRelation = 'http://opds-spec.org/image';
const String opdsThumbnailRelation = 'http://opds-spec.org/image/thumbnail';
const String opdsCoverRelation = 'http://opds-spec.org/cover';
const String thrCoverRelation = 'thr:cover';
const String opdsSortRelationPrefix = 'http://opds-spec.org/sort';
const String opdsSpecRelationPrefix = 'http://opds-spec.org/';
const String opdsSearchRelation = 'http://opds-spec.org/search';
const String opdsSubsectionRelation = 'subsection';

/// One `atom:link` element of an OPDS catalog document.
class OpdsLink {
  const OpdsLink({
    required this.rel,
    required this.href,
    this.type,
    this.title,
  });

  final String rel;

  /// Always absolute: the parser resolves relative hrefs against the URL of
  /// the feed that carried the link, which is how real catalogs (and the
  /// OPDS 1.2 spec's own examples) mix relative and absolute hrefs.
  final Uri href;

  final String? type;
  final String? title;

  /// Any acquisition relation, including the refinements (`/open-access`,
  /// `/sample`, `/borrow`, ...).
  bool get isAcquisition =>
      rel.toLowerCase().startsWith(opdsAcquisitionRelation);

  /// A full-size cover image link.
  bool get isCover =>
      rel == opdsImageRelation ||
      rel == opdsCoverRelation ||
      rel == thrCoverRelation;

  bool get isThumbnail => rel == opdsThumbnailRelation;

  bool get isOpdsSearchFacet {
    final value = rel.toLowerCase();
    // OPDS 1.2 spells the facet `search` (RFC 5988); older catalogs use the
    // explicit `http://opds-spec.org/search` form.
    return value == 'search' || value == opdsSearchRelation;
  }

  /// True when this link points at *another catalog feed*, i.e. what a
  /// navigation entry uses to build the browse hierarchy.
  ///
  /// Deliberately narrow: `self`/`start` point back at the current feed and
  /// `type=entry` documents are single-entry documents, neither of which is
  /// browsable as a sub-catalog.
  bool get isSubCatalogFeed {
    final value = rel.toLowerCase();
    final isBrowseRelation = value == opdsSubsectionRelation ||
        value.startsWith(opdsSortRelationPrefix);
    if (!isBrowseRelation) return false;
    final mediaType = (type ?? '').toLowerCase();
    if (mediaType.isEmpty) return true; // sloppy catalogs omit the type
    return mediaType.contains('application/atom+xml') &&
        !mediaType.contains('type=entry');
  }
}

/// One `atom:entry` of an OPDS catalog feed.
class OpdsEntry {
  const OpdsEntry({
    required this.id,
    required this.title,
    this.authors = const [],
    this.summary,
    this.categories = const [],
    this.links = const [],
    this.updated,
  });

  /// The atom id, which some catalogs (Office of the Historian) ship as an
  /// `xml:id` attribute on an empty `<id/>` element instead of element text.
  final String id;

  final String title;
  final List<String> authors;
  final String? summary;

  /// Category labels (`<category label="..."/>`, falling back to `term`).
  final List<String> categories;

  final List<OpdsLink> links;
  final DateTime? updated;

  List<OpdsLink> get acquisitionLinks =>
      links.where((link) => link.isAcquisition).toList();

  List<OpdsLink> get subCatalogLinks =>
      links.where((link) => link.isSubCatalogFeed).toList();

  /// Best cover available: a full-size image, else a thumbnail. Catalogs
  /// also invent rels like `http://opds-spec.org/cover` and the older
  /// `thr:cover`, so those count too.
  OpdsLink? get coverLink {
    OpdsLink? image;
    OpdsLink? thumbnail;
    for (final link in links) {
      if (link.isThumbnail) {
        thumbnail ??= link;
      } else if (link.isCover) {
        image ??= link;
      }
    }
    return image ?? thumbnail;
  }
}

/// A sub-catalog reachable from a feed, with the best title available —
/// navigation entries carry the title on the entry, the spec's feed-level
/// link style carries it on the link.
class OpdsCatalogRef {
  const OpdsCatalogRef({required this.title, required this.href});

  final String title;
  final Uri href;
}

/// One parsed OPDS catalog feed document (navigation or acquisition).
class OpdsFeed {
  const OpdsFeed({
    required this.title,
    this.links = const [],
    this.entries = const [],
  });

  final String title;

  /// Feed-level `atom:link`s (self/start/up/next/search/...).
  final List<OpdsLink> links;

  final List<OpdsEntry> entries;

  Uri? _firstHrefWhere(bool Function(OpdsLink link) predicate) {
    for (final link in links) {
      if (predicate(link)) return link.href;
    }
    return null;
  }

  Uri? get selfHref => _firstHrefWhere((link) => link.rel == 'self');

  Uri? get startHref => _firstHrefWhere((link) => link.rel == 'start');

  Uri? get upHref => _firstHrefWhere((link) => link.rel == 'up');

  Uri? get nextHref => _firstHrefWhere((link) => link.rel == 'next');

  Uri? get prevHref => _firstHrefWhere((link) => link.rel == 'prev');

  OpdsLink? get searchLink {
    for (final link in links) {
      if (link.isOpdsSearchFacet) return link;
    }
    return null;
  }

  /// Raw links to other catalog feeds: feed-level (the OPDS 1.2 spec's root
  /// example references its acquisition feeds that way) plus every
  /// navigation entry's link.
  List<OpdsLink> get subCatalogLinks => [
        for (final link in links)
          if (link.isSubCatalogFeed) link,
        for (final entry in entries) ...entry.subCatalogLinks,
      ];

  /// [subCatalogLinks] with a display title attached to each.
  List<OpdsCatalogRef> get subCatalogRefs => [
        for (final link in links)
          if (link.isSubCatalogFeed)
            OpdsCatalogRef(title: link.title ?? '', href: link.href),
        for (final entry in entries)
          for (final link in entry.subCatalogLinks)
            OpdsCatalogRef(
              title: entry.title.isNotEmpty ? entry.title : (link.title ?? ''),
              href: link.href,
            ),
      ];

  /// Whether any entry is an actual publication (as opposed to every entry
  /// being a pointer to another feed).
  bool get hasBookEntries =>
      entries.any((entry) => entry.acquisitionLinks.isNotEmpty);
}
