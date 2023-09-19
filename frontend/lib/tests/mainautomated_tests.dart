import 'package:flutter_driver/flutter_driver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_app_name/home_screen.dart';  // Import your HomeScreen widget

void main() {
  testWidgets('Renders HomeScreen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(MaterialApp(home: HomeScreen()));

    // Verify if certain widgets are present
    expect(find.text('Some text you expect to find'), findsOneWidget);
  });
}
