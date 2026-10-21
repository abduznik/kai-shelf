import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/backend_providers.dart';
import 'core/providers/incognito_provider.dart';
import 'core/providers/notification_providers.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/update/update_check_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final incognito = await loadIncognitoFlag();
  final themeMode = await loadThemeMode();
  runApp(ProviderScope(
    overrides: [
      incognitoInitialProvider.overrideWithValue(incognito),
      themeModeInitialProvider.overrideWithValue(themeMode),
    ],
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
    _checkForUpdates();
    _startChapterNotifications();
  }

  /// Asks GitHub for the latest release once the app is up. Fire-and-forget
  /// by contract: it never blocks the first frame, the provider throttles it
  /// to one request a day, and every failure is swallowed inside — so there
  /// is no error dialog on a device without a network.
  Future<void> _checkForUpdates() async {
    try {
      await ref.read(updateCheckProvider.notifier).check();
    } catch (_) {
      // Belt and braces: an update check can never break startup.
    }
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
    // After the restore, so a notification-tap route opens with a backend
    // already available to load the title from.
    await _openNotificationRouteIfAny();
  }

  /// Brings the new-chapter feature online (issue #9): initialise the
  /// notification plugin so taps and cold starts can route, then re-arm the
  /// background schedule when the feature is enabled. A fresh, disabled
  /// install does nothing here beyond the plugin init.
  Future<void> _startChapterNotifications() async {
    final presenter = ref.read(notificationPresenterProvider);
    if (presenter == null) return; // Feature hidden on this platform.
    try {
      await presenter.ensureInitialised();
      await ref.read(notificationControllerProvider)?.start();
    } catch (_) {
      // Notification plumbing can never keep the app from starting; worst
      // case the settings toggle is the only thing that works.
    }
  }

  /// Opens the title a notification announced, when (and only when) the app
  /// was launched by tapping one.
  Future<void> _openNotificationRouteIfAny() async {
    final route =
        await ref.read(notificationPresenterProvider)?.consumeLaunchRoute();
    if (route != null && mounted) appRouter.go(route);
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
      themeMode: ref.watch(themeModeProvider),
      routerConfig: appRouter,
    );
  }
}
