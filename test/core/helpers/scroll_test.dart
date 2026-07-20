import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/helpers/scroll.dart';

void main() {
  testWidgets('starts at latest and follows continuous content growth', (
    tester,
  ) async {
    final controller = ChatScrollController();
    addTearDown(controller.dispose);
    var latestHeight = 40.0;
    StateSetter? setListState;

    await tester.pumpWidget(
      _listApp(
        controller: controller,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            setListState = setState;
            return _notifyingList(
              controller,
              itemCount: 30,
              itemBuilder: (_, i) => SizedBox(
                height: i == 29 ? latestHeight : 40,
                child: Text('Item $i'),
              ),
            );
          },
        ),
      ),
    );

    expect(controller.mode, ChatScrollMode.following);
    expect(controller.position.pixels, controller.position.maxScrollExtent);

    for (var i = 0; i < 5; i++) {
      setListState!(() => latestHeight += 24);
      await tester.pump();
      expect(controller.position.pixels, controller.position.maxScrollExtent);
      expect(controller.mode, ChatScrollMode.following);
    }
  });

  testWidgets('user drag pauses and latest growth preserves reading offset', (
    tester,
  ) async {
    final controller = ChatScrollController();
    addTearDown(controller.dispose);
    var latestHeight = 40.0;
    StateSetter? setListState;

    await tester.pumpWidget(
      _listApp(
        controller: controller,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            setListState = setState;
            return _notifyingList(
              controller,
              itemCount: 30,
              itemBuilder: (_, i) => SizedBox(
                height: i == 29 ? latestHeight : 40,
                child: Text('Item $i'),
              ),
            );
          },
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, 180));
    await tester.pumpAndSettle();

    expect(controller.mode, ChatScrollMode.paused);
    expect(controller.needsReturnToLatest, isTrue);
    final readingOffset = controller.position.pixels;

    setListState!(() => latestHeight += 160);
    await tester.pump();

    expect(controller.position.pixels, readingOffset);
    expect(controller.mode, ChatScrollMode.paused);
  });

  testWidgets('pointer scrolling pauses following immediately', (tester) async {
    final controller = ChatScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _listApp(
        controller: controller,
        builder: (_) => _notifyingList(
          controller,
          itemCount: 30,
          itemBuilder: (_, i) => SizedBox(height: 40, child: Text('Item $i')),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(ListView));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -180)),
    );
    await tester.pump();

    expect(controller.mode, ChatScrollMode.paused);
    expect(controller.needsReturnToLatest, isTrue);
  });

  testWidgets('keyboard scroll actions pause following', (tester) async {
    final controller = ChatScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _listApp(
        controller: controller,
        builder: (_) => _notifyingList(
          controller,
          itemCount: 30,
          itemBuilder: (_, i) => SizedBox(height: 40, child: Text('Item $i')),
        ),
      ),
    );

    final context = tester.element(find.byType(Viewport));
    Actions.invoke(context, const ScrollIntent(direction: AxisDirection.up));
    await tester.pumpAndSettle();

    expect(controller.mode, ChatScrollMode.paused);
    expect(
      controller.position.pixels,
      lessThan(controller.position.maxScrollExtent),
    );
  });

  testWidgets(
    'return reaches the current latest extent and resumes following',
    (tester) async {
      final controller = ChatScrollController();
      addTearDown(controller.dispose);
      var latestHeight = 40.0;
      StateSetter? setListState;

      await tester.pumpWidget(
        _listApp(
          controller: controller,
          builder: (context) => StatefulBuilder(
            builder: (context, setState) {
              setListState = setState;
              return _notifyingList(
                controller,
                itemCount: 30,
                itemBuilder: (_, i) => SizedBox(
                  height: i == 29 ? latestHeight : 40,
                  child: Text('Item $i'),
                ),
              );
            },
          ),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, 180));
      await tester.pumpAndSettle();

      final returning = controller.returnToLatest(
        duration: const Duration(milliseconds: 200),
      );
      await tester.pump(const Duration(milliseconds: 80));
      setListState!(() => latestHeight += 100);
      await tester.pump();
      await tester.pumpAndSettle();
      await returning;

      expect(controller.mode, ChatScrollMode.following);
      expect(controller.position.pixels, controller.position.maxScrollExtent);
    },
  );

  testWidgets('user input interrupts an animated return', (tester) async {
    final controller = ChatScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _listApp(
        controller: controller,
        builder: (_) => _notifyingList(
          controller,
          itemCount: 30,
          itemBuilder: (_, i) => SizedBox(height: 40, child: Text('Item $i')),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    final returning = controller.returnToLatest(
      duration: const Duration(seconds: 1),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pumpAndSettle();
    await returning;

    expect(controller.mode, ChatScrollMode.paused);
    expect(controller.needsReturnToLatest, isTrue);
  });

  testWidgets('long and reduced-motion returns jump immediately', (
    tester,
  ) async {
    final controller = ChatScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _listApp(
        controller: controller,
        builder: (_) => _notifyingList(
          controller,
          itemCount: 200,
          itemBuilder: (_, i) => SizedBox(height: 40, child: Text('Item $i')),
        ),
      ),
    );

    controller.jumpTo(controller.position.minScrollExtent);
    await controller.returnToLatest();
    expect(controller.position.pixels, controller.position.maxScrollExtent);

    controller.jumpTo(controller.position.maxScrollExtent - 100);
    await controller.returnToLatest(animate: false);
    expect(controller.position.pixels, controller.position.maxScrollExtent);
    expect(controller.mode, ChatScrollMode.following);
  });

  testWidgets('viewport resize pins only while following', (tester) async {
    final controller = ChatScrollController();
    addTearDown(controller.dispose);
    var viewportHeight = 240.0;
    StateSetter? setListState;

    await tester.pumpWidget(
      _listApp(
        controller: controller,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            setListState = setState;
            return SizedBox(
              height: viewportHeight,
              child: _notifyingList(
                controller,
                itemCount: 30,
                itemBuilder: (_, i) =>
                    SizedBox(height: 40, child: Text('Item $i')),
              ),
            );
          },
        ),
      ),
    );

    setListState!(() => viewportHeight = 180);
    await tester.pump();
    expect(controller.position.pixels, controller.position.maxScrollExtent);

    await tester.drag(find.byType(ListView), const Offset(0, 180));
    await tester.pumpAndSettle();
    final readingOffset = controller.position.pixels;

    setListState!(() => viewportHeight = 160);
    await tester.pump();
    expect(controller.position.pixels, readingOffset);
    expect(controller.mode, ChatScrollMode.paused);
  });

  testWidgets('restores a paused session before reattaching', (tester) async {
    final first = ChatScrollController();
    addTearDown(first.dispose);

    await tester.pumpWidget(
      _listApp(
        controller: first,
        builder: (_) => _notifyingList(
          first,
          itemCount: 30,
          itemBuilder: (_, i) => SizedBox(height: 40, child: Text('Item $i')),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, 180));
    await tester.pumpAndSettle();
    final snapshot = first.snapshot(historyRevision: 4);

    await tester.pumpWidget(const SizedBox.shrink());

    final restored = ChatScrollController()..restoreSnapshot(snapshot);
    addTearDown(restored.dispose);
    await tester.pumpWidget(
      _listApp(
        controller: restored,
        builder: (_) => _notifyingList(
          restored,
          itemCount: 30,
          itemBuilder: (_, i) => SizedBox(height: 40, child: Text('Item $i')),
        ),
      ),
    );

    expect(restored.mode, ChatScrollMode.paused);
    expect(restored.position.pixels, snapshot.offset);
  });
}

Widget _listApp({
  required ChatScrollController controller,
  required WidgetBuilder builder,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(height: 240, child: Builder(builder: builder)),
    ),
  );
}

Widget _notifyingList(
  ChatScrollController controller, {
  required int itemCount,
  required IndexedWidgetBuilder itemBuilder,
}) {
  return NotificationListener<ScrollNotification>(
    onNotification: (notification) {
      controller.handleScrollNotification(notification);
      return false;
    },
    child: ListView.builder(
      controller: controller,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    ),
  );
}
