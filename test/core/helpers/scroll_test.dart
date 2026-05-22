import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/helpers/scroll.dart';

void main() {
  testWidgets('scrolls to max extent for normal vertical lists', (
    tester,
  ) async {
    final controller = SmartScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 200,
          child: ListView.builder(
            controller: controller,
            itemExtent: 40,
            itemCount: 20,
            itemBuilder: (_, i) => Text('Item $i'),
          ),
        ),
      ),
    );

    controller.jumpTo(controller.position.minScrollExtent);
    expect(controller.isNearBottom, isFalse);

    final scroll = controller.scrollToBottom(
      duration: const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();
    await scroll;

    expect(controller.position.pixels, controller.position.maxScrollExtent);
    expect(controller.isNearBottom, isTrue);
  });

  testWidgets('scrolls to min extent for reversed vertical lists', (
    tester,
  ) async {
    final controller = SmartScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 200,
          child: ListView.builder(
            controller: controller,
            reverse: true,
            itemExtent: 40,
            itemCount: 20,
            itemBuilder: (_, i) => Text('Item $i'),
          ),
        ),
      ),
    );

    controller.jumpTo(controller.position.maxScrollExtent);
    expect(controller.isNearBottom, isFalse);

    final scroll = controller.scrollToBottom(
      duration: const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();
    await scroll;

    expect(controller.position.pixels, controller.position.minScrollExtent);
    expect(controller.isNearBottom, isTrue);
  });
}
