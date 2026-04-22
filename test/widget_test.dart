import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/main.dart';

void main() {
  testWidgets('Pro-Tracker smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProTrackerApp());
    expect(find.text('Pro-Tracker'), findsWidgets);
  });
}
