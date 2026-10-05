import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/models.dart';
import '../backend/server_backend.dart';
import 'backend_providers.dart';

/// Extensions known to the server (installed or not). Empty for backends
/// without [ExtensionCapableBackend]. Use [ExtensionsNotifier.refresh] to
/// make the server re-read its repositories.
final extensionsProvider =
    AsyncNotifierProvider.autoDispose<ExtensionsNotifier, List<KsExtension>>(
        ExtensionsNotifier.new);

class ExtensionsNotifier extends AutoDisposeAsyncNotifier<List<KsExtension>> {
  ExtensionCapableBackend? get _backend {
    final backend = ref.read(activeBackendProvider);
    return backend is ExtensionCapableBackend
        ? backend as ExtensionCapableBackend
        : null;
  }

  @override
  Future<List<KsExtension>> build() async {
    ref.watch(activeBackendProvider);
    return await _backend?.getExtensions() ?? [];
  }

  Future<void> refresh() async {
    final backend = _backend;
    if (backend == null) return;
    state = await AsyncValue.guard(() => backend.getExtensions(refresh: true));
    ref.read(sourceCatalogRefreshProvider.notifier).state++;
  }

  Future<void> install(String pkgName) =>
      _run((b) => b.installExtension(pkgName));
  Future<void> upgrade(String pkgName) =>
      _run((b) => b.updateExtension(pkgName));
  Future<void> uninstall(String pkgName) =>
      _run((b) => b.uninstallExtension(pkgName));

  Future<void> _run(Future<void> Function(ExtensionCapableBackend) op) async {
    final backend = _backend;
    if (backend == null) return;
    await op(backend);
    state = AsyncData(await backend.getExtensions());
    ref.read(sourceCatalogRefreshProvider.notifier).state++;
  }
}

/// Bumped whenever installed extensions change so the source list reloads.
final sourceCatalogRefreshProvider = StateProvider<int>((ref) => 0);

final extensionReposProvider =
    FutureProvider.autoDispose<List<KsExtensionRepo>>((ref) async {
  final backend = ref.watch(activeBackendProvider);
  if (backend is! ExtensionCapableBackend) return [];
  return (backend as ExtensionCapableBackend).getExtensionRepos();
});
