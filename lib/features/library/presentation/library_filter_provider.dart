import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/library_filter.dart';

/// The library's filter/sort state, lifted out of the library screen's local
/// widget state so other screens can hand the library a filter.
///
/// The title screen's genre chips use this: tapping a tag sets that genre as
/// an include filter here and navigates back to the library, and the library
/// reads the same provider for its grid, its search box and the active-count
/// badge on the filter button.
final libraryFilterProvider =
    StateProvider<LibraryFilter>((ref) => const LibraryFilter());
