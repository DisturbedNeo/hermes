import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/model_session_diagnostics.dart';
import 'package:hermes/core/services/model_diagnostic_bundle_writer.dart';

void main() {
  group('ModelDiagnosticBundleWriter', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_diagnostics_');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'persists sanitized failures and retains only the newest ten',
      () async {
        final writer = ModelDiagnosticBundleWriter(
          directoryProvider: () async => root,
        );

        for (var i = 0; i < 12; i++) {
          await writer.writeTransportFailure(
            timestamp: DateTime.utc(2026, 1, 1, 0, 0, i),
            modelName: 'test-model',
            baseUrl: 'http://127.0.0.1:1234',
            serverState: 'ready',
            processRunning: true,
            processId: 42,
            failureKind: 'brokenPipe',
            attempt: 2,
            outputStarted: false,
            error: const SocketException('broken pipe'),
            stackTrace: StackTrace.empty,
            recentLogs: const [
              {
                'timestamp': '2026-01-01T00:00:00Z',
                'source': 'stderr',
                'message': 'request completed normally',
              },
            ],
          );
        }

        final directory = Directory('${root.path}/diagnostics/model-transport');
        final files =
            await directory
                  .list()
                  .where((entity) => entity is File)
                  .cast<File>()
                  .toList()
              ..sort((a, b) => b.path.compareTo(a.path));
        expect(files, hasLength(ModelDiagnosticBundleWriter.maxBundles));

        final bundle = jsonDecode(await files.first.readAsString()) as Map;
        expect(bundle['model'], 'test-model');
        expect(bundle['serverState'], 'ready');
        expect(bundle['processRunning'], isTrue);
        expect((bundle['transport'] as Map)['kind'], 'brokenPipe');
        expect(bundle.toString(), isNot(contains('prompt')));
        expect(bundle.toString(), isNot(contains('request body')));
      },
    );
  });

  test('transport diagnostics do not mark a ready server failed', () {
    final diagnostics = ModelSessionDiagnostics()
      ..state = ModelServerState.ready;
    addTearDown(diagnostics.dispose);

    diagnostics.recordTransportEvent(
      kind: 'brokenPipe',
      attempt: 1,
      willRetry: true,
      outputStarted: false,
      error: const SocketException('broken pipe'),
    );

    expect(diagnostics.state, ModelServerState.ready);
    expect(diagnostics.lastError, isNull);
    expect(diagnostics.logs.single.source, 'transport');
  });
}
