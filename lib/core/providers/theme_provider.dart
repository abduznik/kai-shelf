import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const themeModePrefKey = 'appearance.themeMode';

/// Reads the saved theme choice. main() awaits this before the first frame
/// and feeds it to [themeModeInitialProvider], so the app never flashes the
/// system theme before applying the one the user picked.
Future<ThemeMode> loadThemeMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(themeModePrefKey);
    return ThemeMode.values
        .firstWhere((m) => m.name == stored, orElse: () => ThemeMode.system);
  } catch (_) {
    return ThemeMode.system;
  }
}

/// What the app boots with until the persisted choice has been applied.
/// main() overrides this with [loadThemeMode]; tests override it directly.
final themeModeInitialProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

/// Theme override: system / light / dark, persisted across restarts.
/// Same Notifier shape as the reader defaults: an eagerly kick-started load
/// plus a setter that flips state first so the UI reacts in the same frame.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  Future<void>? _loading;

  /// Completes once the persisted choice has been applied. Callers (and
  /// tests) await this instead of racing the initial load.
  Future<void> get ready => _loading ??= _load();

  @override
  ThemeMode build() {
    _loading = null;
    ready;
    return ref.watch(themeModeInitialProvider);
  }

  Future<void> _load() async {
    try {
      final mode = await loadThemeMode();
      if (mode != state) state = mode;
    } catch (_) {
      // The container can go away while storage is being read (test
      // cleanup, app teardown); there is no state left to update.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await ready;
    // State flips first so the very next frame renders with the new theme;
    // the write to disk can lag behind without weakening the guarantee.
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(themeModePrefKey, mode.name);
    } catch (_) {
      // Not persisting only means the choice resets on restart.
    }
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
