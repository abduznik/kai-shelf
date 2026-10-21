import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/providers/reader_prefs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('global reading direction', () {
    test('defaults to left-to-right', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(readingDirectionProvider.notifier).ready;
      expect(container.read(readingDirectionProvider), ReadingDirection.ltr);
    });

    test('an RTL choice survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(readingDirectionProvider.notifier).ready;
      await container
          .read(readingDirectionProvider.notifier)
          .setDirection(ReadingDirection.rtl);
      expect(await loadReadingDirection(), ReadingDirection.rtl);

      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      await restarted.read(readingDirectionProvider.notifier).ready;
      expect(restarted.read(readingDirectionProvider), ReadingDirection.rtl);
    });
  });

  group('resolveReaderPreferences', () {
    test('no override follows the global setting exactly', () {
      final prefs = resolveReaderPreferences(
        globalMode: ReaderMode.webtoon,
        globalDirection: ReadingDirection.rtl,
      );
      expect(prefs.mode, ReaderMode.webtoon);
      expect(prefs.direction, ReadingDirection.rtl);
    });

    test('an override wins over the global default', () {
      final prefs = resolveReaderPreferences(
        globalMode: ReaderMode.paged,
        globalDirection: ReadingDirection.ltr,
        override: const ReaderTitleOverride(
          mode: ReaderMode.webtoon,
          direction: ReadingDirection.rtl,
        ),
      );
      expect(prefs.mode, ReaderMode.webtoon);
      expect(prefs.direction, ReadingDirection.rtl);
    });

    test('override fields left unset fall back to the global setting', () {
      final prefs = resolveReaderPreferences(
        globalMode: ReaderMode.webtoon,
        globalDirection: ReadingDirection.rtl,
        override: const ReaderTitleOverride(mode: ReaderMode.paged),
      );
      expect(prefs.mode, ReaderMode.paged);
      expect(prefs.direction, ReadingDirection.rtl);
    });
  });

  group('per-title overrides', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
      await container.read(readerTitleOverridesProvider.notifier).ready;
    });

    tearDown(() => container.dispose());

    test('are keyed by manga id and survive a restart', () async {
      final notifier = container.read(readerTitleOverridesProvider.notifier);
      await notifier.setMode('manga-1', ReaderMode.webtoon);
      await notifier.setDirection('manga-1', ReadingDirection.rtl);

      final saved = await loadReaderTitleOverrides();
      expect(saved['manga-1']?.mode, ReaderMode.webtoon);
      expect(saved['manga-1']?.direction, ReadingDirection.rtl);
      expect(saved.containsKey('manga-2'), isFalse);

      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      await restarted.read(readerTitleOverridesProvider.notifier).ready;
      final restored = restarted.read(readerTitleOverridesProvider);
      expect(restored['manga-1']?.mode, ReaderMode.webtoon);
      expect(restored['manga-1']?.direction, ReadingDirection.rtl);
    });

    test('changing one setting keeps the other per-title choice', () async {
      final notifier = container.read(readerTitleOverridesProvider.notifier);
      await notifier.setDirection('manga-1', ReadingDirection.rtl);
      await notifier.setMode('manga-1', ReaderMode.webtoon);
      final override = container.read(readerTitleOverridesProvider)['manga-1'];
      expect(override?.mode, ReaderMode.webtoon);
      expect(override?.direction, ReadingDirection.rtl);
    });

    test('titles without an override follow the global setting', () async {
      final notifier = container.read(readerTitleOverridesProvider.notifier);
      await notifier.setMode('manga-1', ReaderMode.webtoon);

      final overridden = container.read(readerPreferencesProvider('manga-1'));
      final untouched = container.read(readerPreferencesProvider('manga-2'));
      expect(overridden.mode, ReaderMode.webtoon);
      expect(untouched.mode, ReaderMode.paged);
      expect(untouched.direction, ReadingDirection.ltr);
    });

    test('the effective preferences honour the override then the global',
        () async {
      final notifier = container.read(readerTitleOverridesProvider.notifier);
      await notifier.setDirection('manga-1', ReadingDirection.rtl);
      await container
          .read(readingDirectionProvider.notifier)
          .setDirection(ReadingDirection.ltr);
      await container
          .read(readerModeProvider.notifier)
          .setMode(ReaderMode.paged);

      final prefs = container.read(readerPreferencesProvider('manga-1'));
      expect(prefs.direction, ReadingDirection.rtl,
          reason: 'the per-title direction wins');
      expect(prefs.mode, ReaderMode.paged,
          reason: 'a title with no mode override falls back to global');
    });

    test('reset clears the override so the global default applies again',
        () async {
      final notifier = container.read(readerTitleOverridesProvider.notifier);
      await notifier.setMode('manga-1', ReaderMode.webtoon);
      await notifier.setDirection('manga-1', ReadingDirection.rtl);
      expect(container.read(readerPreferencesProvider('manga-1')).mode,
          ReaderMode.webtoon);

      await notifier.clear('manga-1');
      expect(
          container.read(readerTitleOverridesProvider).containsKey('manga-1'),
          isFalse);
      final prefs = container.read(readerPreferencesProvider('manga-1'));
      expect(prefs.mode, ReaderMode.paged);
      expect(prefs.direction, ReadingDirection.ltr);
      expect(
          (await loadReaderTitleOverrides()).containsKey('manga-1'), isFalse);
    });
  });
}
