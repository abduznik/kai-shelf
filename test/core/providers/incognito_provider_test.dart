import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/providers/incognito_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to off', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await loadIncognitoFlag(), isFalse);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(incognitoProvider), isFalse);
  });

  test('toggle flips state immediately and persists across a restart',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final pending = container.read(incognitoProvider.notifier).setEnabled(true);
    // State is visible before the disk write completes.
    expect(container.read(incognitoProvider), isTrue);
    await pending;

    // "Restart": main() reloads the flag and seeds a fresh container.
    final saved = await loadIncognitoFlag();
    expect(saved, isTrue);
    final restarted = ProviderContainer(
        overrides: [incognitoInitialProvider.overrideWithValue(saved)]);
    addTearDown(restarted.dispose);
    expect(restarted.read(incognitoProvider), isTrue);

    await restarted.read(incognitoProvider.notifier).setEnabled(false);
    expect(await loadIncognitoFlag(), isFalse);
  });
}
