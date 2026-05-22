import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/ui/common/state_display.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty state fits the reported tiny viewport', (tester) async {
    await _setViewport(tester, const Size(172, 127));

    await tester.pumpWidget(
      const _StateDisplayApp(
        child: StateDisplay(
          state: DisplayState.empty,
          emptyMessage: 'No saved chats',
          emptyHint: 'Create a new chat to get started',
          icon: Icons.chat_bubble_outline,
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('error state with retry fits a very short viewport', (
    tester,
  ) async {
    await _setViewport(tester, const Size(160, 96));

    await tester.pumpWidget(
      _StateDisplayApp(
        child: StateDisplay(
          state: DisplayState.error,
          errorMessage: 'Failed to load chats',
          onRetry: () {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

class _StateDisplayApp extends StatelessWidget {
  final Widget child;

  const _StateDisplayApp({required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: Scaffold(body: child));
  }
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
