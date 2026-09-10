import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kai_shelf/main.dart';

void main() {
  testWidgets('KaiShelfApp boots to the add-server screen with bottom nav',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: KaiShelfApp()));
    await tester.pumpAndSettle();

    expect(find.text('Connect to a server — coming in M1'), findsOneWidget);
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
