enum ModelCallStatus {
  starting,
  processingPrompt,
  generating,
  completed,
  failed,
  cancelled,
}

enum TelemetryAccuracy { exact, partial, estimated }

class ModelCallDiagnostics {
  final String callId;
  final String label;
  final ModelCallStatus status;
  final DateTime startedAt;
  final DateTime? firstOutputAt;
  final DateTime? completedAt;
  final String? serverRequestId;
  final String? systemFingerprint;
  final String? finishReason;
  final String? error;
  final int? contextLimitTokens;
  final int? promptTokens;
  final int? cachedPromptTokens;
  final int? processedPromptTokens;
  final int? generatedTokens;
  final int? promptProgressTotal;
  final int? promptProgressCached;
  final int? promptProgressProcessed;
  final double? promptProgressMs;
  final double? promptMs;
  final double? generationMs;
  final double? promptTokensPerSecond;
  final double? generationTokensPerSecond;
  final int? draftTokens;
  final int? acceptedDraftTokens;
  final TelemetryAccuracy accuracy;
  final bool promptTokensExact;
  final bool generatedTokensExact;
  final bool cachedPromptTokensExact;

  const ModelCallDiagnostics({
    required this.callId,
    required this.label,
    required this.status,
    required this.startedAt,
    required this.accuracy,
    this.firstOutputAt,
    this.completedAt,
    this.serverRequestId,
    this.systemFingerprint,
    this.finishReason,
    this.error,
    this.contextLimitTokens,
    this.promptTokens,
    this.cachedPromptTokens,
    this.processedPromptTokens,
    this.generatedTokens,
    this.promptProgressTotal,
    this.promptProgressCached,
    this.promptProgressProcessed,
    this.promptProgressMs,
    this.promptMs,
    this.generationMs,
    this.promptTokensPerSecond,
    this.generationTokensPerSecond,
    this.draftTokens,
    this.acceptedDraftTokens,
    this.promptTokensExact = false,
    this.generatedTokensExact = false,
    this.cachedPromptTokensExact = false,
  });

  bool get isActive => switch (status) {
    ModelCallStatus.starting ||
    ModelCallStatus.processingPrompt ||
    ModelCallStatus.generating => true,
    _ => false,
  };

  int? get contextTokens {
    final prompt = promptTokens;
    if (prompt == null) return null;
    return prompt + (generatedTokens ?? 0);
  }

  bool get contextIsExact =>
      promptTokensExact && (generatedTokens == null || generatedTokensExact);

  double? get estimatedGenerationTokensPerSecond {
    if (generatedTokensExact ||
        generatedTokens == null ||
        firstOutputAt == null) {
      return null;
    }
    final end = completedAt ?? DateTime.now();
    final seconds = end.difference(firstOutputAt!).inMilliseconds / 1000;
    return seconds <= 0 ? null : generatedTokens! / seconds;
  }

  double? get promptProgressFraction {
    final total = promptProgressTotal ?? promptTokens;
    final processed = promptProgressProcessed;
    if (total == null || total <= 0 || processed == null) return null;
    return ((processed + (promptProgressCached ?? 0)) / total).clamp(0.0, 1.0);
  }

  Duration? get timeToFirstToken {
    final first = firstOutputAt;
    if (first == null) return null;
    return first.difference(startedAt);
  }

  Duration? get endToEndDuration {
    final completed = completedAt;
    if (completed == null) return null;
    return completed.difference(startedAt);
  }

  double? get speculativeAcceptanceRatio {
    final drafted = draftTokens;
    final accepted = acceptedDraftTokens;
    if (drafted == null || drafted <= 0 || accepted == null) return null;
    return accepted / drafted;
  }

  Map<String, dynamic> toSafeJson() => {
    'callId': callId,
    'label': label,
    'status': status.name,
    'accuracy': accuracy.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (firstOutputAt != null)
      'firstOutputAt': firstOutputAt!.toUtc().toIso8601String(),
    if (completedAt != null)
      'completedAt': completedAt!.toUtc().toIso8601String(),
    if (serverRequestId != null) 'serverRequestId': serverRequestId,
    if (systemFingerprint != null) 'systemFingerprint': systemFingerprint,
    if (finishReason != null) 'finishReason': finishReason,
    if (contextLimitTokens != null) 'contextLimitTokens': contextLimitTokens,
    if (promptTokens != null) 'promptTokens': promptTokens,
    if (cachedPromptTokens != null) 'cachedPromptTokens': cachedPromptTokens,
    if (processedPromptTokens != null)
      'processedPromptTokens': processedPromptTokens,
    if (generatedTokens != null) 'generatedTokens': generatedTokens,
    if (promptProgressTotal != null) 'promptProgressTotal': promptProgressTotal,
    if (promptProgressCached != null)
      'promptProgressCached': promptProgressCached,
    if (promptProgressProcessed != null)
      'promptProgressProcessed': promptProgressProcessed,
    if (promptProgressMs != null) 'promptProgressMs': promptProgressMs,
    if (promptMs != null) 'promptMs': promptMs,
    if (generationMs != null) 'generationMs': generationMs,
    if (promptTokensPerSecond != null)
      'promptTokensPerSecond': promptTokensPerSecond,
    if (generationTokensPerSecond != null)
      'generationTokensPerSecond': generationTokensPerSecond,
    if (draftTokens != null) 'draftTokens': draftTokens,
    if (acceptedDraftTokens != null) 'acceptedDraftTokens': acceptedDraftTokens,
    'promptTokensExact': promptTokensExact,
    'generatedTokensExact': generatedTokensExact,
    'cachedPromptTokensExact': cachedPromptTokensExact,
  };
}

class ModelSessionTotals {
  final int callsStarted;
  final int callsCompleted;
  final int callsFailed;
  final int callsCancelled;
  final int promptTokens;
  final int generatedTokens;
  final int cachedPromptTokens;
  final int draftTokens;
  final int acceptedDraftTokens;
  final double promptMs;
  final double generationMs;
  final Duration endToEndDuration;
  final Duration timeToFirstTokenTotal;
  final int timeToFirstTokenSamples;
  final int exactCalls;
  final int fallbackCalls;

  const ModelSessionTotals({
    this.callsStarted = 0,
    this.callsCompleted = 0,
    this.callsFailed = 0,
    this.callsCancelled = 0,
    this.promptTokens = 0,
    this.generatedTokens = 0,
    this.cachedPromptTokens = 0,
    this.draftTokens = 0,
    this.acceptedDraftTokens = 0,
    this.promptMs = 0,
    this.generationMs = 0,
    this.endToEndDuration = Duration.zero,
    this.timeToFirstTokenTotal = Duration.zero,
    this.timeToFirstTokenSamples = 0,
    this.exactCalls = 0,
    this.fallbackCalls = 0,
  });

  int get callsFinished => callsCompleted + callsFailed + callsCancelled;

  double? get promptTokensPerSecond =>
      promptMs > 0 ? promptTokens * 1000 / promptMs : null;

  double? get generationTokensPerSecond =>
      generationMs > 0 ? generatedTokens * 1000 / generationMs : null;

  double? get cacheHitRatio =>
      promptTokens > 0 ? cachedPromptTokens / promptTokens : null;

  double? get speculativeAcceptanceRatio =>
      draftTokens > 0 ? acceptedDraftTokens / draftTokens : null;

  Duration? get averageTimeToFirstToken => timeToFirstTokenSamples == 0
      ? null
      : Duration(
          microseconds:
              timeToFirstTokenTotal.inMicroseconds ~/ timeToFirstTokenSamples,
        );
}

class LlamaServerProperties {
  final int? effectiveContextSize;
  final int? totalSlots;
  final String? modelPath;
  final String? buildInfo;
  final Map<String, dynamic> chatTemplateCapabilities;
  final Map<String, dynamic> modalities;

  const LlamaServerProperties({
    this.effectiveContextSize,
    this.totalSlots,
    this.modelPath,
    this.buildInfo,
    this.chatTemplateCapabilities = const {},
    this.modalities = const {},
  });

  Map<String, dynamic> toSafeJson() => {
    if (effectiveContextSize != null)
      'effectiveContextSize': effectiveContextSize,
    if (totalSlots != null) 'totalSlots': totalSlots,
    if (modelPath != null) 'modelPath': modelPath,
    if (buildInfo != null) 'buildInfo': buildInfo,
    if (chatTemplateCapabilities.isNotEmpty)
      'chatTemplateCapabilities': chatTemplateCapabilities,
    if (modalities.isNotEmpty) 'modalities': modalities,
  };
}
