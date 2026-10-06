import 'package:flutter_test/flutter_test.dart';
import 'package:kai_shelf/core/backend/models.dart';
import 'package:kai_shelf/features/extensions/presentation/extension_filter.dart';

void main() {
  const all = [
    KsExtension(pkgName: 'a.b', name: 'Beta', lang: 'en', isInstalled: true),
    KsExtension(
        pkgName: 'a.u',
        name: 'Alpha',
        lang: 'en',
        isInstalled: true,
        hasUpdate: true),
    KsExtension(pkgName: 'a.f', name: 'Fuego', lang: 'es'),
    KsExtension(
        pkgName: 'a.n',
        name: 'Nsfw',
        lang: 'en',
        contentWarning: ContentWarning.nsfw),
    KsExtension(pkgName: 'a.o', name: 'Old', lang: 'en', isObsolete: true),
    KsExtension(
        pkgName: 'a.oi',
        name: 'OldInstalled',
        lang: 'en',
        isInstalled: true,
        isObsolete: true),
  ];

  test('orders updates, installed, then available; hides uninstalled obsolete',
      () {
    expect(const ExtensionFilter().apply(all).map((e) => e.name),
        ['Alpha', 'Beta', 'OldInstalled', 'Fuego', 'Nsfw']);
  });

  test('status filters', () {
    expect(
        const ExtensionFilter(status: ExtensionStatus.updates)
            .apply(all)
            .map((e) => e.name),
        ['Alpha']);
    expect(
        const ExtensionFilter(status: ExtensionStatus.available)
            .apply(all)
            .map((e) => e.name),
        ['Fuego', 'Nsfw']);
  });

  test('language, nsfw and query filters', () {
    expect(const ExtensionFilter(languages: {'es'}).apply(all).single.name,
        'Fuego');
    expect(
        const ExtensionFilter(hideNsfw: true)
            .apply(all)
            .any((e) => e.name == 'Nsfw'),
        isFalse);
    expect(const ExtensionFilter(query: 'ALP').apply(all).single.name, 'Alpha');
    expect(ExtensionFilter.languagesOf(all), ['en', 'es']);
  });
}
