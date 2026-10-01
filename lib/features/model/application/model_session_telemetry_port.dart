/// Internal write/telemetry capability for model and chat runtime services.
/// Presentation consumers must depend on [ModelSessionDiagnosticsPort] only.
abstract interface class ModelSessionTelemetryPort {
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
