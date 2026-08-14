// This is a basic Flutter widget test for Crimson Prism.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:crystalapp/main.dart';

void main() {
  testWidgets('Home screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CrystalApp());

    // Verify that our home screen loads and displays the app bar title and section headers.
    expect(find.text('CRIMSON PRISM'), findsOneWidget);
    expect(find.text('HISTORIAS'), findsOneWidget);
  });
}
