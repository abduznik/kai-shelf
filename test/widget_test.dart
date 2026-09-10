import 'package:flutter_test/flutter_test.dart';

import 'package:kai_shelf/main.dart';

void main() {
  testWidgets('KaiShelfApp shows the coming soon screen', (WidgetTester tester) async {
    await tester.pumpWidget(const KaiShelfApp());

    expect(find.text('Kai-Shelf — Coming Soon'), findsOneWidget);
  });
}
