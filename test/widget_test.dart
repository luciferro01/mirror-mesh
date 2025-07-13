// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mirror_mesh/main.dart';

void main() {
  testWidgets('Mirror Mesh app loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: MirrorMeshApp()));

    // Verify that the app title is displayed.
    expect(find.text('Mirror Mesh'), findsWidgets);

    // Verify that the share screen button is present.
    expect(find.text('Share Screen'), findsOneWidget);

    // Verify that the quick actions section is present.
    expect(find.text('Quick Actions'), findsOneWidget);
  });
}
