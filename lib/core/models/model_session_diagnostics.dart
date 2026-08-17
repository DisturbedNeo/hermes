import 'package:flutter/foundation.dart';
import 'package:hermes/core/helpers/chat/throttled_scheduler.dart';
import 'package:hermes/core/models/model_call_diagnostics.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';

enum ModelServerState { stopped, starting, ready, failed, cancelled }

class ModelSessionLogEntry {
  final DateTime timestamp;
  final String source;
  final String message;

  const ModelSessionLogEntry({
    required this.timestamp,
    required this.source,
    required this.message,
  });
}

class ModelSessionDiagnostics extends ChangeNotifier {
  static const int _maxLogEntries = 1000;
  static const Duration _streamOutputNotifyInterval = Duration(
    milliseconds: 500,
  );

  ModelServerState state = ModelServerState.stopped;
  ModelConfigurationSnapshot? modelSnapshot;
  String? baseUrl;
  int? port;
  String? executablePath;
  DateTime? startupStartedAt;
  DateTime? startupReadyAt;
  Duration? startupDuration;
  String? lastError;
  String? recentFailureOutput;
  LlamaServerProperties? serverProperties;
  ModelSessionTotals sessionTotals = const ModelSessionTotals();
  bool liveTelemetryEnabled = false;

  bool isStreaming = false;
  int? estimatedContextTokens;
  int? contextLimitTokens;
  bool compactionActive = false;
  String? lastCompactionStatus;
  int? lastCompactionTokensSaved;
  int? lastCompactionMessagesCovered;

  final List<ModelSessionLogEntry> _logs = [];
  final Map<String, ModelCallDiagnostics> _calls = {};
  final Map<String, DateTime> _callUpdatedAt = {};
  final Set<String> _finalizedCallIds = {};
  DateTime? _estimateUpdatedAt;
  late final ThrottledScheduler _streamOutputNotifier;

  ModelSessionDiagnostics() {
    _streamOutputNotifier = ThrottledScheduler(
      interval: _streamOutputNotifyInterval,
      onTick: notifyListeners,
    );
  }

  List<ModelSessionLogEntry> get logs => List.unmodifiable(_logs);

  Iterable<ModelCallDiagnostics> get activeCalls =>
      _calls.values.where((call) => call.isActive);

  int get activeCallCount => activeCalls.length;

  ModelCallDiagnostics? get activeCall {
    final active = activeCalls.toList();
    if (active.isEmpty) return null;
    active.sort(
      (a, b) => (_callUpdatedAt[b.callId] ?? b.startedAt).compareTo(
        _callUpdatedAt[a.callId] ?? a.startedAt,
      ),
    );
    return active.first;
  }

  ModelCallDiagnostics? get lastCall {
    if (_calls.isEmpty) return null;
    final calls = _calls.values.toList()
      ..sort(
        (a, b) => (_callUpdatedAt[b.callId] ?? b.startedAt).compareTo(
          _callUpdatedAt[a.callId] ?? a.startedAt,
        ),
      );
    return calls.first;
  }

  ModelCallDiagnostics? get displayCall => activeCall ?? lastCall;

  bool get displayContextIsEstimate {
    if (activeCall != null) {
      return !activeCall!.contextIsExact;
    }
    final call = lastCall;
    final estimateAt = _estimateUpdatedAt;
    final callAt = call == null ? null : _callUpdatedAt[call.callId];
    if (estimatedContextTokens != null &&
        estimateAt != null &&
        (callAt == null || estimateAt.isAfter(callAt))) {
      return true;
    }
    return call != null && !call.contextIsExact;
  }

  int? get displayContextTokens {
    final active = activeCall;
    if (active != null) return active.contextTokens;
    final call = lastCall;
    final estimateAt = _estimateUpdatedAt;
    final callAt = call == null ? null : _callUpdatedAt[call.callId];
    if (estimatedContextTokens != null &&
        estimateAt != null &&
        (callAt == null || estimateAt.isAfter(callAt))) {
      return estimatedContextTokens;
    }
    return call?.contextTokens ?? estimatedContextTokens;
  }

  void recordStarting({
    required ModelConfigurationSnapshot snapshot,
    required int port,
    required String baseUrl,
    required String executablePath,
  }) {
    state = ModelServerState.starting;
    modelSnapshot = snapshot;
    this.port = port;
    this.baseUrl = baseUrl;
    this.executablePath = executablePath;
    startupStartedAt = DateTime.now();
    startupReadyAt = null;
    startupDuration = null;
    lastError = null;
    recentFailureOutput = null;
    serverProperties = null;
    contextLimitTokens = snapshot.nCtx;
    _resetCallMetrics();
    _resetStreamMetrics();
    addLog('lifecycle', 'Starting ${snapshot.modelName} on $baseUrl');
    notifyListeners();
  }

  void recordReady() {
    state = ModelServerState.ready;
    startupReadyAt = DateTime.now();
    final started = startupStartedAt;
    startupDuration = started == null
        ? null
        : startupReadyAt!.difference(started);
    addLog('lifecycle', 'Server ready');
    notifyListeners();
  }

  void recordStopped() {
    state = ModelServerState.stopped;
    _resetStreamMetrics();
    addLog('lifecycle', 'Server stopped');
    notifyListeners();
  }

  void recordCancelled() {
    state = ModelServerState.cancelled;
    _resetStreamMetrics();
    addLog('lifecycle', 'Startup cancelled');
    notifyListeners();
  }

  void recordFailure(Object error, {String? recentOutput}) {
    state = ModelServerState.failed;
    lastError = error.toString();
    recentFailureOutput = recentOutput;
    _resetStreamMetrics();
    addLog('error', lastError!);
    notifyListeners();
  }

  void recordProcessExit(int exitCode) {
    addLog('process', 'llama-server exited with code $exitCode');
    if (state == ModelServerState.ready || state == ModelServerState.starting) {
      state = exitCode == 0
          ? ModelServerState.stopped
          : ModelServerState.failed;
      if (exitCode != 0) {
        lastError = 'llama-server exited with code $exitCode';
      }
      _resetStreamMetrics();
    }
    notifyListeners();
  }

  void setLiveTelemetryEnabled(bool enabled) {
    liveTelemetryEnabled = enabled;
  }

  void recordCallDiagnostics(ModelCallDiagnostics value) {
    final previous = _calls[value.callId];
    final isNew = previous == null;
    _calls[value.callId] = value;
    _callUpdatedAt[value.callId] = DateTime.now();
    if (value.status == ModelCallStatus.failed && value.error != null) {
      lastError = value.error;
    }

    if (isNew) {
      sessionTotals = _copyTotals(callsStarted: sessionTotals.callsStarted + 1);
    }

    if (!value.isActive && _finalizedCallIds.add(value.callId)) {
      final ttft = value.timeToFirstToken;
      final e2e = value.endToEndDuration;
      sessionTotals = _copyTotals(
        callsCompleted:
            sessionTotals.callsCompleted +
            (value.status == ModelCallStatus.completed ? 1 : 0),
        callsFailed:
            sessionTotals.callsFailed +
            (value.status == ModelCallStatus.failed ? 1 : 0),
        callsCancelled:
            sessionTotals.callsCancelled +
            (value.status == ModelCallStatus.cancelled ? 1 : 0),
        promptTokens:
            sessionTotals.promptTokens +
            (value.promptTokensExact ? value.promptTokens ?? 0 : 0),
        generatedTokens:
            sessionTotals.generatedTokens +
            (value.generatedTokensExact ? value.generatedTokens ?? 0 : 0),
        cachedPromptTokens:
            sessionTotals.cachedPromptTokens +
            (value.cachedPromptTokensExact ? value.cachedPromptTokens ?? 0 : 0),
        draftTokens: sessionTotals.draftTokens + (value.draftTokens ?? 0),
        acceptedDraftTokens:
            sessionTotals.acceptedDraftTokens +
            (value.acceptedDraftTokens ?? 0),
        promptMs: sessionTotals.promptMs + (value.promptMs ?? 0),
        generationMs: sessionTotals.generationMs + (value.generationMs ?? 0),
        endToEndDuration:
            sessionTotals.endToEndDuration + (e2e ?? Duration.zero),
        timeToFirstTokenTotal:
            sessionTotals.timeToFirstTokenTotal + (ttft ?? Duration.zero),
        timeToFirstTokenSamples:
            sessionTotals.timeToFirstTokenSamples + (ttft == null ? 0 : 1),
        exactCalls:
            sessionTotals.exactCalls +
            (value.accuracy == TelemetryAccuracy.exact ? 1 : 0),
        fallbackCalls:
            sessionTotals.fallbackCalls +
            (value.accuracy == TelemetryAccuracy.estimated ? 1 : 0),
      );
    }

    isStreaming = activeCallCount > 0;
    final phaseChanged = previous?.status != value.status;
    if (phaseChanged || !value.isActive) {
      _streamOutputNotifier.cancel();
      notifyListeners();
    } else {
      _streamOutputNotifier.schedule();
    }
  }

  void recordServerProperties(LlamaServerProperties value) {
    serverProperties = value;
    contextLimitTokens = value.effectiveContextSize ?? contextLimitTokens;
    notifyListeners();
  }

  void updateContextEstimate(
    int? estimatedContextTokens, {
    int? contextLimitTokens,
  }) {
    this.estimatedContextTokens = estimatedContextTokens;
    _estimateUpdatedAt = DateTime.now();
    this.contextLimitTokens = contextLimitTokens ?? this.contextLimitTokens;
    notifyListeners();
  }

  void recordTransportEvent({
    required String kind,
    required int attempt,
    required bool willRetry,
    required bool outputStarted,
    required Object error,
  }) {
    final action = willRetry ? 'retrying' : 'request paused';
    addLog(
      'transport',
      '$kind on attempt $attempt ($action, outputStarted=$outputStarted): '
          '$error',
    );
    if (!willRetry) {
      lastError = error.toString();
    }
    notifyListeners();
  }

  void recordCompactionStarted(String status) {
    compactionActive = true;
    lastCompactionStatus = status;
    addLog('compaction', status);
    notifyListeners();
  }

  void recordCompactionStatus(String status) {
    lastCompactionStatus = status;
    addLog('compaction', status);
    notifyListeners();
  }

  void recordCompactionFinished({
    required String status,
    int? tokensSaved,
    int? messagesCovered,
  }) {
    compactionActive = false;
    lastCompactionStatus = status;
    if (tokensSaved != null) {
      lastCompactionTokensSaved = tokensSaved;
    }
    if (messagesCovered != null) {
      lastCompactionMessagesCovered = messagesCovered;
    }
    addLog('compaction', status);
    notifyListeners();
  }

  void recordCompactionFailed(Object error) {
    compactionActive = false;
    lastError = error.toString();
    lastCompactionStatus = 'Context compaction failed: $error';
    addLog('compaction', lastCompactionStatus!);
    notifyListeners();
  }

  void addLog(String source, String output) {
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    for (final line in lines) {
      _logs.add(
        ModelSessionLogEntry(
          timestamp: DateTime.now(),
          source: source,
          message: line,
        ),
      );
    }

    if (_logs.length > _maxLogEntries) {
      _logs.removeRange(0, _logs.length - _maxLogEntries);
    }

    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _streamOutputNotifier.cancel();
    super.dispose();
  }

  void _resetStreamMetrics() {
    _streamOutputNotifier.cancel();
    isStreaming = false;
    estimatedContextTokens = null;
    compactionActive = false;
  }

  void _resetCallMetrics() {
    _calls.clear();
    _callUpdatedAt.clear();
    _finalizedCallIds.clear();
    sessionTotals = const ModelSessionTotals();
    _estimateUpdatedAt = null;
  }

  ModelSessionTotals _copyTotals({
    int? callsStarted,
    int? callsCompleted,
    int? callsFailed,
    int? callsCancelled,
    int? promptTokens,
    int? generatedTokens,
    int? cachedPromptTokens,
    int? draftTokens,
    int? acceptedDraftTokens,
    double? promptMs,
    double? generationMs,
    Duration? endToEndDuration,
    Duration? timeToFirstTokenTotal,
    int? timeToFirstTokenSamples,
    int? exactCalls,
    int? fallbackCalls,
  }) => ModelSessionTotals(
    callsStarted: callsStarted ?? sessionTotals.callsStarted,
    callsCompleted: callsCompleted ?? sessionTotals.callsCompleted,
    callsFailed: callsFailed ?? sessionTotals.callsFailed,
    callsCancelled: callsCancelled ?? sessionTotals.callsCancelled,
    promptTokens: promptTokens ?? sessionTotals.promptTokens,
    generatedTokens: generatedTokens ?? sessionTotals.generatedTokens,
    cachedPromptTokens: cachedPromptTokens ?? sessionTotals.cachedPromptTokens,
    draftTokens: draftTokens ?? sessionTotals.draftTokens,
    acceptedDraftTokens:
        acceptedDraftTokens ?? sessionTotals.acceptedDraftTokens,
    promptMs: promptMs ?? sessionTotals.promptMs,
    generationMs: generationMs ?? sessionTotals.generationMs,
    endToEndDuration: endToEndDuration ?? sessionTotals.endToEndDuration,
    timeToFirstTokenTotal:
        timeToFirstTokenTotal ?? sessionTotals.timeToFirstTokenTotal,
    timeToFirstTokenSamples:
        timeToFirstTokenSamples ?? sessionTotals.timeToFirstTokenSamples,
    exactCalls: exactCalls ?? sessionTotals.exactCalls,
    fallbackCalls: fallbackCalls ?? sessionTotals.fallbackCalls,
  );
}
