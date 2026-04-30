import 'package:flutter/foundation.dart';
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
  static const int _maxLogEntries = 300;

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

  bool isStreaming = false;
  DateTime? streamStartedAt;
  DateTime? streamEndedAt;
  int streamOutputCharacters = 0;
  int? estimatedContextTokens;
  int? contextLimitTokens;
  bool compactionActive = false;
  String? lastCompactionStatus;
  int? lastCompactionTokensSaved;
  int? lastCompactionMessagesCovered;

  final List<ModelSessionLogEntry> _logs = [];

  List<ModelSessionLogEntry> get logs => List.unmodifiable(_logs);

  double? get streamTokensPerSecond {
    final started = streamStartedAt;
    final estimatedOutputTokens = streamOutputCharacters / 4;
    if (started == null || estimatedOutputTokens <= 0) return null;

    final ended = isStreaming ? DateTime.now() : streamEndedAt;
    final duration = (ended ?? DateTime.now()).difference(started);
    final seconds = duration.inMilliseconds / 1000;
    if (seconds <= 0) return null;

    return estimatedOutputTokens / seconds;
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
    contextLimitTokens = snapshot.nCtx;
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

  void recordStreamStarted({
    int? estimatedContextTokens,
    int? contextLimitTokens,
  }) {
    isStreaming = true;
    streamStartedAt = DateTime.now();
    streamEndedAt = null;
    streamOutputCharacters = 0;
    this.estimatedContextTokens = estimatedContextTokens;
    this.contextLimitTokens = contextLimitTokens ?? this.contextLimitTokens;
    notifyListeners();
  }

  void recordStreamOutput(String text) {
    if (!isStreaming || text.isEmpty) return;
    streamOutputCharacters += text.length;
    notifyListeners();
  }

  void updateContextEstimate(
    int? estimatedContextTokens, {
    int? contextLimitTokens,
  }) {
    this.estimatedContextTokens = estimatedContextTokens;
    this.contextLimitTokens = contextLimitTokens ?? this.contextLimitTokens;
    notifyListeners();
  }

  void recordStreamEnded() {
    if (!isStreaming) return;
    isStreaming = false;
    streamEndedAt = DateTime.now();
    notifyListeners();
  }

  void recordStreamError(Object error) {
    lastError = error.toString();
    recordStreamEnded();
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

  void _resetStreamMetrics() {
    isStreaming = false;
    streamStartedAt = null;
    streamEndedAt = null;
    streamOutputCharacters = 0;
    estimatedContextTokens = null;
    compactionActive = false;
  }
}
