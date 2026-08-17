import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/model_call_diagnostics.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/model_session_diagnostics.dart';

void main() {
  group('ModelSessionDiagnostics', () {
    test(
      'isolates concurrent calls and keeps the most recently progressing',
      () {
        final diagnostics = ModelSessionDiagnostics();
        addTearDown(diagnostics.dispose);
        final now = DateTime(2026, 1, 1);

        diagnostics.recordCallDiagnostics(
          _call('first', now, status: ModelCallStatus.generating),
        );
        diagnostics.recordCallDiagnostics(
          _call(
            'second',
            now.add(const Duration(seconds: 1)),
            status: ModelCallStatus.processingPrompt,
          ),
        );

        expect(diagnostics.activeCallCount, 2);
        expect(diagnostics.activeCall?.callId, 'second');

        diagnostics.recordCallDiagnostics(
          _call(
            'first',
            now,
            status: ModelCallStatus.generating,
            generatedTokens: 2,
          ),
        );
        expect(diagnostics.activeCall?.callId, 'first');
      },
    );

    test('aggregates a finalized call once with weighted rates', () {
      final diagnostics = ModelSessionDiagnostics();
      addTearDown(diagnostics.dispose);
      final started = DateTime(2026, 1, 1);
      final completed = _call(
        'done',
        started,
        status: ModelCallStatus.completed,
        completedAt: started.add(const Duration(seconds: 2)),
        firstOutputAt: started.add(const Duration(milliseconds: 500)),
        promptTokens: 100,
        cachedPromptTokens: 25,
        generatedTokens: 20,
        promptMs: 100,
        generationMs: 400,
        draftTokens: 10,
        acceptedDraftTokens: 8,
      );

      diagnostics.recordCallDiagnostics(completed);
      diagnostics.recordCallDiagnostics(completed);

      final totals = diagnostics.sessionTotals;
      expect(totals.callsStarted, 1);
      expect(totals.callsCompleted, 1);
      expect(totals.promptTokens, 100);
      expect(totals.generatedTokens, 20);
      expect(totals.cacheHitRatio, 0.25);
      expect(totals.promptTokensPerSecond, 1000);
      expect(totals.generationTokensPerSecond, 50);
      expect(totals.averageTimeToFirstToken, const Duration(milliseconds: 500));
      expect(totals.speculativeAcceptanceRatio, 0.8);
    });

    test(
      'counts partial exact data but excludes estimates from token totals',
      () {
        final diagnostics = ModelSessionDiagnostics();
        addTearDown(diagnostics.dispose);
        final now = DateTime(2026, 1, 1);

        diagnostics.recordCallDiagnostics(
          _call(
            'partial',
            now,
            status: ModelCallStatus.cancelled,
            accuracy: TelemetryAccuracy.partial,
            promptTokens: 80,
            generatedTokens: 7,
          ),
        );
        diagnostics.recordCallDiagnostics(
          _call(
            'estimate',
            now,
            status: ModelCallStatus.failed,
            accuracy: TelemetryAccuracy.estimated,
            promptTokens: 400,
            generatedTokens: 20,
          ),
        );

        expect(diagnostics.sessionTotals.promptTokens, 80);
        expect(diagnostics.sessionTotals.generatedTokens, 7);
        expect(diagnostics.sessionTotals.callsCancelled, 1);
        expect(diagnostics.sessionTotals.callsFailed, 1);
        expect(diagnostics.sessionTotals.fallbackCalls, 1);
      },
    );

    test(
      'a later idle estimate supersedes old exact context and start resets',
      () {
        final diagnostics = ModelSessionDiagnostics();
        addTearDown(diagnostics.dispose);
        final now = DateTime(2026, 1, 1);
        diagnostics.recordCallDiagnostics(
          _call(
            'done',
            now,
            status: ModelCallStatus.completed,
            promptTokens: 100,
            generatedTokens: 10,
          ),
        );
        expect(diagnostics.displayContextTokens, 110);
        expect(diagnostics.displayContextIsEstimate, isFalse);

        diagnostics.updateContextEstimate(150, contextLimitTokens: 4096);
        expect(diagnostics.displayContextTokens, 150);
        expect(diagnostics.displayContextIsEstimate, isTrue);

        diagnostics.recordStarting(
          snapshot: _snapshot,
          port: 1234,
          baseUrl: 'http://127.0.0.1:1234',
          executablePath: '/llama/llama-server',
        );
        expect(diagnostics.sessionTotals.callsStarted, 0);
        expect(diagnostics.lastCall, isNull);
        expect(diagnostics.displayContextTokens, isNull);
      },
    );
  });
}

ModelCallDiagnostics _call(
  String id,
  DateTime startedAt, {
  required ModelCallStatus status,
  TelemetryAccuracy accuracy = TelemetryAccuracy.exact,
  DateTime? firstOutputAt,
  DateTime? completedAt,
  int? promptTokens,
  int? cachedPromptTokens,
  int? generatedTokens,
  double? promptMs,
  double? generationMs,
  int? draftTokens,
  int? acceptedDraftTokens,
}) => ModelCallDiagnostics(
  callId: id,
  label: id,
  status: status,
  startedAt: startedAt,
  accuracy: accuracy,
  firstOutputAt: firstOutputAt,
  completedAt: completedAt,
  promptTokens: promptTokens,
  cachedPromptTokens: cachedPromptTokens,
  generatedTokens: generatedTokens,
  promptMs: promptMs,
  generationMs: generationMs,
  draftTokens: draftTokens,
  acceptedDraftTokens: acceptedDraftTokens,
  promptTokensExact:
      promptTokens != null && accuracy != TelemetryAccuracy.estimated,
  generatedTokensExact:
      generatedTokens != null && accuracy != TelemetryAccuracy.estimated,
  cachedPromptTokensExact:
      cachedPromptTokens != null && accuracy != TelemetryAccuracy.estimated,
);

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
