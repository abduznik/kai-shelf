import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kai_shelf/features/library/presentation/library_screen.dart';

void main() {
  testWidgets('LibraryScreen prompts to connect when no server is active',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/library',
      routes: [
        GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: Text('home'))),
        GoRoute(
            path: '/library',
            builder: (context, state) => const LibraryScreen()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not connected to a server yet.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  });
}
