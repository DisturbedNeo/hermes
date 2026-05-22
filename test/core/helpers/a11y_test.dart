import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/helpers/a11y.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ScalableText clamps text scaling without changing base style', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3)),
        child: const MaterialApp(
          home: Scaffold(
            body: ScalableText(
              data: 'Scaled text',
              style: TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('Scaled text'));

    expect(text.style?.fontSize, 20);
    expect(text.textScaler?.scale(20), 40);
  });
}
