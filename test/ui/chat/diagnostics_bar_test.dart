import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/diagnostics_visibility.dart';
import 'package:hermes/core/helpers/preferences_keys.dart';
import 'package:hermes/core/models/model_call_diagnostics.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/model_session_diagnostics.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/ui/chat/diagnostics_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferencesService preferences;
  late ModelSessionDiagnostics diagnostics;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    preferences = PreferencesService();
    diagnostics = ModelSessionDiagnostics()
      ..state = ModelServerState.ready
      ..modelSnapshot = _snapshot
      ..contextLimitTokens = 4096;
  });

  tearDown(() {
    preferences.dispose();
    diagnostics.dispose();
  });

  testWidgets('off hides diagnostics and disables live telemetry', (
    tester,
  ) async {
    await _pump(tester, preferences, diagnostics);

    expect(find.textContaining('Status:'), findsNothing);
    expect(diagnostics.liveTelemetryEnabled, isFalse);
  });

  testWidgets('compact shows exact operational telemetry', (tester) async {
    preferences.dispose();
    SharedPreferences.setMockInitialValues({
      PreferencesKeys.diagnosticsVisibility: DiagnosticsVisibility.compact.name,
    });
    preferences = PreferencesService();
    diagnostics.recordCallDiagnostics(
      ModelCallDiagnostics(
        callId: 'call-1',
        label: 'Chat response',
        status: ModelCallStatus.generating,
        startedAt: DateTime(2026, 1, 1),
        accuracy: TelemetryAccuracy.exact,
        promptTokens: 100,
        generatedTokens: 20,
        contextLimitTokens: 4096,
        generationTokensPerSecond: 42.5,
        promptTokensExact: true,
        generatedTokensExact: true,
      ),
    );

    await _pump(tester, preferences, diagnostics);

    expect(find.textContaining('Status: Generating · Chat response'), findsOne);
    expect(find.text('Speed: 42.5 t/s'), findsOne);
    expect(find.textContaining('Context: 120 / 4,096'), findsOne);
    expect(find.textContaining('est.'), findsNothing);
    expect(diagnostics.liveTelemetryEnabled, isTrue);
  });

  testWidgets('detailed groups call, totals, runtime, and configuration', (
    tester,
  ) async {
    preferences.dispose();
    SharedPreferences.setMockInitialValues({
      PreferencesKeys.diagnosticsVisibility:
          DiagnosticsVisibility.detailed.name,
    });
    preferences = PreferencesService();
    diagnostics
      ..recordServerProperties(
        const LlamaServerProperties(
          effectiveContextSize: 4096,
          totalSlots: 1,
          buildInfo: 'build-42',
          modelPath: '/models/model.gguf',
          chatTemplateCapabilities: {'tools': true},
          modalities: {'text': true},
        ),
      )
      ..recordCallDiagnostics(
        ModelCallDiagnostics(
          callId: 'call-1',
          label: 'Task planning',
          status: ModelCallStatus.completed,
          startedAt: DateTime(2026, 1, 1),
          completedAt: DateTime(2026, 1, 1, 0, 0, 2),
          accuracy: TelemetryAccuracy.exact,
          serverRequestId: 'request-123',
          promptTokens: 100,
          cachedPromptTokens: 50,
          generatedTokens: 20,
          promptMs: 100,
          generationMs: 400,
          contextLimitTokens: 4096,
          promptTokensExact: true,
          generatedTokensExact: true,
          cachedPromptTokensExact: true,
        ),
      );

    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester, preferences, diagnostics);

    expect(find.text('Active / last call'), findsOne);
    expect(find.text('Call timing'), findsOne);
    expect(find.text('Session totals'), findsOne);
    expect(find.text('Server / runtime'), findsOne);
    expect(find.text('Configuration · compute'), findsOne);
    expect(find.text('GPU layers: All'), findsOne);
    expect(find.text('Request ID: request-123'), findsOne);
    expect(find.text('Build: build-42'), findsOne);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  PreferencesService preferences,
  ModelSessionDiagnostics diagnostics,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: DiagnosticsBar(
            diagnostics: diagnostics,
            preferencesService: preferences,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

const _snapshot = ModelConfigurationSnapshot(
  modelName: 'model',
  modelPath: '/models/model.gguf',
  llamaCppDirectory: '/llama.cpp',
  nCtx: 4096,
  nThreads: 8,
  temperature: 0.7,
  topP: 0.9,
  topK: 40,
  nBatch: 2048,
  nUBatch: 512,
  mirostat: 0,
  repeatPenalty: 1.1,
  repeatLastN: 256,
  presencePenalty: 0,
  frequencyPenalty: 0,
  thinking: true,
  flashAttention: true,
  cachePrompt: true,
  cacheReuse: 256,
  kvCacheQuantizationEnabled: true,
  kvCacheTypeK: 'q8_0',
  kvCacheTypeV: 'q8_0',
);
