import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haken_dran/app.dart';

void main() {
  testWidgets('App startet ohne Fehler', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: HakenDranApp()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
