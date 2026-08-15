import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pusaka/app.dart';

void main() {
  testWidgets('App renders Home Screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PusakaApp(),
      ),
    );
    // Pump frames to complete flutter_animate timers
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
