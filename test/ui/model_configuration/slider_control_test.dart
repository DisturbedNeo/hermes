import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/ui/model_configuration/slider_control.dart';

void main() {
  testWidgets('integer text input updates value without submit', (
    tester,
  ) async {
    var value = 8;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SliderControl.integer(
            label: 'Context (K)',
            value: value,
            min: 1,
            max: 256,
            onChanged: (next) => value = next,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), '256');

    expect(value, 256);
  });

  testWidgets('lays out without overflow at narrow widths', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 327,
              child: SliderControl.integer(
                label: 'Context (K)',
                value: 8,
                min: 1,
                max: 256,
                step: 8,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SliderControl<int>), findsOneWidget);
  });
}
