import 'package:flutter_test/flutter_test.dart';
import 'package:chess_app/main.dart';

void main() {
  testWidgets('Chess app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ChessApp());

    // Verify that the title is present
    expect(find.text('Chess Game'), findsOneWidget);
  });
}
