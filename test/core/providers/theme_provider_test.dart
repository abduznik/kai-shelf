import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('theme override', () {
    test('defaults to following the system theme', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(themeModeProvider.notifier).ready;
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('a choice applies immediately and survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(themeModeProvider.notifier).ready;

      await container
          .read(themeModeProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      expect(container.read(themeModeProvider), ThemeMode.dark,
          reason: 'the new theme must apply without waiting for a reload');
      expect(await loadThemeMode(), ThemeMode.dark,
          reason: 'the choice must be persisted');

      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      await restarted.read(themeModeProvider.notifier).ready;
      expect(restarted.read(themeModeProvider), ThemeMode.dark);
    });

    test('a boot with the persisted choice applied by main reads it', () async {
      SharedPreferences.setMockInitialValues(
          {themeModePrefKey: ThemeMode.light.name});
      final mode = await loadThemeMode();
      expect(mode, ThemeMode.light);

      final container = ProviderContainer(
        overrides: [themeModeInitialProvider.overrideWithValue(mode)],
      );
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.light,
          reason: 'the first frame already renders with the saved theme');
    });

    test('an unreadable stored value falls back to the system theme', () async {
      SharedPreferences.setMockInitialValues({themeModePrefKey: 'neon'});
      expect(await loadThemeMode(), ThemeMode.system);
    });
  });
}
