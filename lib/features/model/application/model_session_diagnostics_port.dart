import 'package:flutter/foundation.dart';
import 'package:hermes/shared_kernel/model_call_diagnostics.dart';
import 'package:hermes/shared_kernel/model_configuration.dart';
import 'package:hermes/shared_kernel/model_session_contracts.dart';

/// Presentation-safe model-session diagnostics capability.
abstract interface class ModelSessionDiagnosticsPort implements Listenable {
  ModelServerState get state;
  ModelConfigurationSnapshot? get modelSnapshot;
  String? get baseUrl;
  String? get executablePath;
  Duration? get startupDuration;
  int? get contextLimitTokens;
  bool get compactionActive;
  String? get lastCompactionStatus;
  int? get lastCompactionMessagesCovered;
  int? get lastCompactionTokensSaved;
  String? get lastError;
  LlamaServerProperties? get serverProperties;
  ModelSessionTotals get sessionTotals;
  List<ModelSessionLogEntry> get logs;
  ModelCallDiagnostics? get activeCall;
  ModelCallDiagnostics? get displayCall;
  ModelCallDiagnostics? get lastCall;
  int get activeCallCount;
  int? get displayContextTokens;
  bool get displayContextIsEstimate;

  void setLiveTelemetryEnabled(bool enabled);
  void updateContextEstimate(
    int? estimatedContextTokens, {
    int? contextLimitTokens,
  });
  void recordCompactionStarted(String status);
  void recordCompactionStatus(String status);
  void recordCompactionFinished({
    required String status,
    int? tokensSaved,
    int? messagesCovered,
  });
  void recordCompactionFailed(Object error);
  void clearLogs();
}
