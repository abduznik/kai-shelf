import 'dart:convert';

/// Route- and folder-safe ids for OPDS entries and acquisition files.
///
/// OPDS has no stable per-publication endpoint — an entry only exists inside
/// the feed that listed it — so an entry id carries *where* it came from:
/// the feed URL plus the entry's own atom id. Chapter ids carry the
/// acquisition file URL itself, which is everything `getPages` needs.
///
/// Everything is base64url without padding because these ids travel inside
/// `'/manga/:mangaId'` and `'/reader/:mangaId/:chapterId'` path segments and
/// become on-disk folder names: no '/', no percent-escapes, no spaces.

/// Encodes the feed [feedUrl] and the [entryKey] (the entry's atom id, or
/// `#index` when the catalog omits ids) into one opaque id.
String encodeOpdsEntryRef(
        {required String feedUrl, required String entryKey}) =>
    _encode('$feedUrl\n$entryKey');

/// Reverses [encodeOpdsEntryRef].
({String feedUrl, String entryKey}) decodeOpdsEntryRef(String id) {
  final decoded = _decode(id);
  final separator = decoded.indexOf('\n');
  if (separator <= 0 || separator == decoded.length - 1) {
    throw const FormatException('Not a Kai-Shelf OPDS entry id.');
  }
  return (
    feedUrl: decoded.substring(0, separator),
    entryKey: decoded.substring(separator + 1),
  );
}

/// Encodes an acquisition file URL into a chapter id.
String encodeOpdsAcquisition(String url) => _encode(url);

/// Reverses [encodeOpdsAcquisition].
Uri decodeOpdsAcquisition(String chapterId) {
  final uri = Uri.tryParse(_decode(chapterId));
  if (uri == null || !uri.hasScheme) {
    throw const FormatException('Not a Kai-Shelf OPDS acquisition id.');
  }
  return uri;
}

String _encode(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

String _decode(String id) {
  final normalized = id.replaceAll('=', '');
  final padded = '$normalized${'=' * ((4 - normalized.length % 4) % 4)}';
  try {
    return utf8.decode(base64Url.decode(padded));
  } on FormatException {
    throw FormatException('Not a Kai-Shelf OPDS id: $id');
  }
}
