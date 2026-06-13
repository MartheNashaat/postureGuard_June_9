import 'package:flutter_test/flutter_test.dart';
import 'package:postureguard/main.dart';

void main() {
  testWidgets('App launches with PostureGuard title', (WidgetTester tester) async {
    await tester.pumpWidget(const PostureGuardApp());
    expect(find.text('PostureGuard'), findsWidgets);
  });
}
