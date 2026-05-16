import 'package:flutter_test/flutter_test.dart';
import 'package:Chess/main.dart';

void main() {
  testWidgets('Chess app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const Chess());

    // Verify that the title is present
    expect(find.text('Chess Game'), findsOneWidget);
  });
}
