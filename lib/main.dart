import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/backend_providers.dart';
import 'core/providers/incognito_provider.dart';
import 'core/router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final incognito = await loadIncognitoFlag();
  runApp(ProviderScope(
    overrides: [incognitoInitialProvider.overrideWithValue(incognito)],
    child: const KaiShelfApp(),
  ));
}

class KaiShelfApp extends ConsumerStatefulWidget {
  const KaiShelfApp({super.key});

  @override
  ConsumerState<KaiShelfApp> createState() => _KaiShelfAppState();
}

class _KaiShelfAppState extends ConsumerState<KaiShelfApp> {
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  /// Signs back in with the saved connection, so reopening the app lands
  /// on the library instead of the connect screen.
  Future<void> _restoreSession() async {
    final restored = await ref.read(sessionStoreProvider).restore();
    if (restored != null) {
      ref.read(activeConnectionProvider.notifier).state = restored;
      appRouter.go('/library');
    }
    if (mounted) setState(() => _restoring = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp.router(
      title: 'Kai-Shelf',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
