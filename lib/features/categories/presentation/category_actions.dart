import 'package:flutter/material.dart';

import '../../../core/backend/server_backend.dart';
import 'category_picker_sheet.dart';

/// Shows the category picker for [mangaId] and applies the choice: adds the
/// manga to the library first when needed (Suwayomi categories only hold
/// library manga), then sets its categories.
Future<CategoryOutcome> pickAndApplyCategories(
  BuildContext context, {
  required Object? backend,
  required String mangaId,
  required bool inLibrary,
}) async {
  if (backend is! CategoryCapableBackend) return CategoryOutcome.cancelled;
  final categories = backend;
  final pick = await showModalBottomSheet<CategoryPick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CategoryPickerSheet(
      backend: categories,
      mangaId: mangaId,
      inLibrary: inLibrary,
      canRemove: backend is SourceCapableBackend,
    ),
  );
  if (pick == null) return CategoryOutcome.cancelled;

  if (pick.removeFromLibrary) {
    await (backend as SourceCapableBackend).removeFromLibrary(mangaId);
    return CategoryOutcome.removed;
  }
  if (!inLibrary && backend is SourceCapableBackend) {
    await (backend as SourceCapableBackend).addToLibrary(mangaId);
  }
  await categories.setMangaCategories(mangaId, pick.categoryIds);
  return inLibrary ? CategoryOutcome.updated : CategoryOutcome.added;
}
