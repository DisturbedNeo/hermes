import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/ui/chat/message/markdown_view.dart';

void main() {
  testWidgets('renders unlabeled fenced code blocks without language errors', (
    tester,
  ) async {
    final previousDebugPrint = debugPrint;
    final debugMessages = <String?>[];
    debugPrint = (message, {wrapWidth}) => debugMessages.add(message);

    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownView(
              data: '''
Unlabeled code:

```
final value = 1;
```
''',
            ),
          ),
        ),
      );
      await tester.pump();
    } finally {
      debugPrint = previousDebugPrint;
    }

    expect(tester.takeException(), isNull);
    expect(
      debugMessages.where(
        (message) => message?.startsWith('get language error:') ?? false,
      ),
      isEmpty,
    );
    expect(find.textContaining('final value = 1;'), findsOneWidget);
  });
}
