import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/cancellation_token.dart';

void main() {
  group('CancellationToken', () {
    test('is idempotent and waits for registered cleanup', () async {
      final token = CancellationToken();
      var callbacks = 0;
      token.onCancel(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        callbacks++;
      });

      await Future.wait([token.cancel(), token.cancel()]);

      expect(token.isCancelled, isTrue);
      expect(callbacks, 1);
      expect(
        token.throwIfCancelled,
        throwsA(isA<OperationCancelledException>()),
      );
    });

    test('runs registrations made after cancellation', () async {
      final token = CancellationToken();
      final called = Completer<void>();
      await token.cancel();

      token.onCancel(called.complete);

      await called.future;
    });
  });
}
