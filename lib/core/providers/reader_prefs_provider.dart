import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderMode { paged, webtoon }

/// Page order for paged reading. Webtoon mode is a vertical scroll, so it
/// has no page direction and ignores this entirely.
enum ReadingDirection { ltr, rtl }

const _readerModeKey = 'reader.mode';
const readerDirectionKey = 'reader.direction';
const readerOverridesKey = 'reader.title_overrides';

/// Reads the globally saved [ReaderMode]. The notifier loads this itself;
/// the helper exists for eager loading and tests.
Future<ReaderMode> loadReaderMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_readerModeKey);
    return ReaderMode.values
        .firstWhere((m) => m.name == stored, orElse: () => ReaderMode.paged);
  } catch (_) {
    return ReaderMode.paged;
  }
}

/// Reads the globally saved [ReadingDirection]; missing or unreadable
/// storage means the long-standing default, left-to-right.
Future<ReadingDirection> loadReadingDirection() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(readerDirectionKey);
    return ReadingDirection.values.firstWhere((d) => d.name == stored,
        orElse: () => ReadingDirection.ltr);
  } catch (_) {
    return ReadingDirection.ltr;
  }
}

/// Reads the per-title overrides map (manga id → [ReaderTitleOverride]).
Future<Map<String, ReaderTitleOverride>> loadReaderTitleOverrides() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(readerOverridesKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    final overrides = <String, ReaderTitleOverride>{};
    for (final entry in decoded.entries) {
      final id = entry.key;
      final value = entry.value;
      if (id is! String || value is! Map) continue;
      overrides[id] =
          ReaderTitleOverride.fromJson(value.cast<String, dynamic>());
    }
    return overrides;
  } catch (_) {
    return {};
  }
}

/// A reading choice made while reading one title, kept apart from the
/// global defaults. Both fields are nullable: an unset field keeps
/// following the global default, so changing one setting never silently
/// pins the other.
class ReaderTitleOverride {
  const ReaderTitleOverride({this.mode, this.direction});

  factory ReaderTitleOverride.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'];
    final directionName = json['direction'];
    return ReaderTitleOverride(
      mode: ReaderMode.values.where((m) => m.name == modeName).firstOrNull,
      direction: ReadingDirection.values
          .where((d) => d.name == directionName)
          .firstOrNull,
    );
  }

  final ReaderMode? mode;
  final ReadingDirection? direction;

  Map<String, Object?> toJson() => {
        if (mode != null) 'mode': mode!.name,
        if (direction != null) 'direction': direction!.name,
      };

  @override
  bool operator ==(Object other) =>
      other is ReaderTitleOverride &&
      other.mode == mode &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(mode, direction);
}

/// The reading configuration a title actually opens with.
class ReaderPreferences {
  const ReaderPreferences({required this.mode, required this.direction});

  final ReaderMode mode;
  final ReadingDirection direction;
}

/// Resolves what a title should open with: the per-title override when it
/// exists, otherwise the global defaults. This is the single place that
/// decides "override first, global fallback", so it stays unit-testable
/// without any storage or widget plumbing.
ReaderPreferences resolveReaderPreferences({
  required ReaderMode globalMode,
  required ReadingDirection globalDirection,
  ReaderTitleOverride? override,
}) =>
    ReaderPreferences(
      mode: override?.mode ?? globalMode,
      direction: override?.direction ?? globalDirection,
    );

class ReaderModeNotifier extends Notifier<ReaderMode> {
  Future<void>? _loading;

  /// Completes once the persisted mode has been applied. Callers (and
  /// tests) await this instead of racing the initial load.
  Future<void> get ready => _loading ??= _load();

  @override
  ReaderMode build() {
    _loading = null;
    ready;
    return ReaderMode.paged;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_readerModeKey);
    if (stored == ReaderMode.webtoon.name) {
      state = ReaderMode.webtoon;
    }
  }

  Future<void> setMode(ReaderMode mode) async {
    await ready;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_readerModeKey, mode.name);
  }
}

final readerModeProvider = NotifierProvider<ReaderModeNotifier, ReaderMode>(
  ReaderModeNotifier.new,
);

/// Global reading direction for paged mode, the twin of
/// [readerModeProvider]. Usually written from the settings screen; the
/// reader overlay writes a per-title override instead.
class ReadingDirectionNotifier extends Notifier<ReadingDirection> {
  Future<void>? _loading;

  /// Completes once the persisted direction has been applied.
  Future<void> get ready => _loading ??= _load();

  @override
  ReadingDirection build() {
    _loading = null;
    ready;
    return ReadingDirection.ltr;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(readerDirectionKey);
    final parsed =
        ReadingDirection.values.where((d) => d.name == stored).firstOrNull;
    if (parsed != null) state = parsed;
  }

  Future<void> setDirection(ReadingDirection direction) async {
    await ready;
    state = direction;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(readerDirectionKey, direction.name);
  }
}

final readingDirectionProvider =
    NotifierProvider<ReadingDirectionNotifier, ReadingDirection>(
  ReadingDirectionNotifier.new,
);

/// Per-title reading choices, keyed by manga id. Whatever the reader
/// overlay changes is remembered for that title only and beats the global
/// defaults until the title is reset.
class ReaderTitleOverridesNotifier
    extends Notifier<Map<String, ReaderTitleOverride>> {
  Future<void>? _loading;

  /// Completes once the persisted overrides have been applied.
  Future<void> get ready => _loading ??= _load();

  @override
  Map<String, ReaderTitleOverride> build() {
    _loading = null;
    ready;
    return const {};
  }

  Future<void> _load() async {
    state = await loadReaderTitleOverrides();
  }

  Future<void> _save(Map<String, ReaderTitleOverride> next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      readerOverridesKey,
      jsonEncode({
        for (final entry in next.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  /// Remembers the title's page mode, leaving its direction alone.
  Future<void> setMode(String mangaId, ReaderMode mode) async {
    await ready;
    final current = state[mangaId] ?? const ReaderTitleOverride();
    await _save({
      ...state,
      mangaId: ReaderTitleOverride(mode: mode, direction: current.direction),
    });
  }

  /// Remembers the title's direction, leaving its mode alone.
  Future<void> setDirection(String mangaId, ReadingDirection direction) async {
    await ready;
    final current = state[mangaId] ?? const ReaderTitleOverride();
    await _save({
      ...state,
      mangaId: ReaderTitleOverride(mode: current.mode, direction: direction),
    });
  }

  /// Drops the title's choices so it follows the global defaults again.
  Future<void> clear(String mangaId) async {
    await ready;
    if (!state.containsKey(mangaId)) return;
    final next = {...state}..remove(mangaId);
    await _save(next);
  }
}

final readerTitleOverridesProvider = NotifierProvider<
    ReaderTitleOverridesNotifier, Map<String, ReaderTitleOverride>>(
  ReaderTitleOverridesNotifier.new,
);

/// What a given title actually opens with: its own override where set, the
/// global defaults everywhere else.
final readerPreferencesProvider = Provider.family<ReaderPreferences, String>(
  (ref, mangaId) => resolveReaderPreferences(
    globalMode: ref.watch(readerModeProvider),
    globalDirection: ref.watch(readingDirectionProvider),
    override: ref.watch(readerTitleOverridesProvider)[mangaId],
  ),
);
