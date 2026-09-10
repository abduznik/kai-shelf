import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/add_server_screen.dart';
import '../../features/downloads/presentation/downloads_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/reader/presentation/reader_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../shell/app_shell.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const AddServerScreen(),
        ),
        GoRoute(
          path: '/library',
          builder: (context, state) => const LibraryScreen(),
        ),
        GoRoute(
          path: '/downloads',
          builder: (context, state) => const DownloadsScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/reader/:mangaId/:chapterId',
      builder: (context, state) => ReaderScreen(
        mangaId: state.pathParameters['mangaId']!,
        chapterId: state.pathParameters['chapterId']!,
      ),
    ),
  ],
);
