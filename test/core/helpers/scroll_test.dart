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

  testWidgets('jumps immediately for long scroll-to-bottom distances', (
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
            itemCount: 200,
            itemBuilder: (_, i) => Text('Item $i'),
          ),
        ),
      ),
    );

    controller.jumpTo(controller.position.maxScrollExtent);
    expect(controller.isNearBottom, isFalse);

    final scroll = controller.scrollToBottom(
      duration: const Duration(milliseconds: 200),
    );

    expect(controller.position.pixels, controller.position.minScrollExtent);
    await scroll;
    expect(controller.isNearBottom, isTrue);
  });

  testWidgets('keeps reversed lists anchored when bottom content grows', (
    tester,
  ) async {
    final controller = SmartScrollController();
    addTearDown(controller.dispose);
    var latestItemHeight = 40.0;
    StateSetter? setListState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setListState = setState;
            return SizedBox(
              height: 200,
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  controller.updateContentMetrics();
                  return false;
                },
                child: ListView.builder(
                  controller: controller,
                  reverse: true,
                  itemCount: 20,
                  itemBuilder: (_, i) {
                    return SizedBox(
                      height: i == 0 ? latestItemHeight : 40,
                      child: Text('Item $i'),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );

    controller.updateContentMetrics();
    controller.jumpTo(120);
    controller.updateAutoScrollState();
    expect(controller.isNearBottom, isFalse);

    setListState!(() => latestItemHeight += 80);
    await tester.pump();
    controller.updateContentMetrics();

    expect(controller.position.pixels, 200);
  });

  testWidgets('does not preserve reversed list offsets while near bottom', (
    tester,
  ) async {
    final controller = SmartScrollController();
    addTearDown(controller.dispose);
    var latestItemHeight = 40.0;
    StateSetter? setListState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setListState = setState;
            return SizedBox(
              height: 200,
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  controller.updateContentMetrics();
                  return false;
                },
                child: ListView.builder(
                  controller: controller,
                  reverse: true,
                  itemCount: 20,
                  itemBuilder: (_, i) {
                    return SizedBox(
                      height: i == 0 ? latestItemHeight : 40,
                      child: Text('Item $i'),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );

    controller.updateContentMetrics();
    controller.jumpTo(controller.position.minScrollExtent);
    controller.updateAutoScrollState();
    expect(controller.isNearBottom, isTrue);

    setListState!(() => latestItemHeight += 80);
    await tester.pump();
    controller.updateContentMetrics();

    expect(controller.position.pixels, controller.position.minScrollExtent);
  });

  testWidgets('does not preserve reversed list offsets on viewport resize', (
    tester,
  ) async {
    final controller = SmartScrollController();
    addTearDown(controller.dispose);
    var viewportHeight = 200.0;
    StateSetter? setListState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setListState = setState;
            return SizedBox(
              height: viewportHeight,
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  controller.updateContentMetrics();
                  return false;
                },
                child: ListView.builder(
                  controller: controller,
                  reverse: true,
                  itemExtent: 40,
                  itemCount: 20,
                  itemBuilder: (_, i) => Text('Item $i'),
                ),
              ),
            );
          },
        ),
      ),
    );

    controller.updateContentMetrics();
    controller.jumpTo(120);
    controller.updateAutoScrollState();
    expect(controller.isNearBottom, isFalse);

    setListState!(() => viewportHeight = 160);
    await tester.pump();
    controller.updateContentMetrics();

    expect(controller.position.pixels, 120);
  });
}
