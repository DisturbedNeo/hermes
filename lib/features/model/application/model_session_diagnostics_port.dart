import 'package:flutter/foundation.dart';
import 'package:hermes/features/model/application/model_call_diagnostics.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/model/application/model_session_contracts.dart';

/// Presentation-safe model-session diagnostics capability.
abstract interface class ModelSessionDiagnosticsPort implements Listenable {
  ModelServerState get state;
  ModelConfigurationSnapshot? get modelSnapshot;
  String? get baseUrl;
  int? get port;
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
}
