import 'package:flutter/foundation.dart';
import 'package:hermes/features/model/application/model_session_diagnostics_port.dart';
import 'package:hermes/features/model/application/model_session_telemetry_port.dart';
import 'package:hermes/core/disposable.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/model/domain/model_provider.dart';

/// Read-only lifecycle state for the active model session.
class ModelSessionState {
  const ModelSessionState({this.snapshot, this.isActive = false});

  final ModelConfigurationSnapshot? snapshot;
  final bool isActive;

  String? get modelName => snapshot?.modelName;
}

/// Result of validating model files before a session restore.
class ModelConfigurationAvailability {
  const ModelConfigurationAvailability({
    this.modelPathMissing = false,
    this.mtpModelPathMissing = false,
  });

  final bool modelPathMissing;
  final bool mtpModelPathMissing;

  bool get available => !modelPathMissing && !mtpModelPathMissing;
}

/// Observable session capability. Implementations may use any notifier
/// internally, but callers can only observe the immutable [value].
abstract interface class ModelSessionPort
    implements ValueListenable<ModelSessionState> {}

/// Application-facing lifecycle port for the local model server.
///
/// Chat depends on this capability rather than on process or HTTP adapters.
abstract interface class ModelServerPort implements Disposable {
  ModelSessionPort get session;
  ModelSessionDiagnosticsPort get diagnostics;
  ModelSessionTelemetryPort get telemetry;
  ModelProvider? get completionProvider;

  Future<ModelConfigurationAvailability> validateConfiguration(
    ModelConfigurationSnapshot snapshot,
  );

  Future<void> startWithSnapshot(ModelConfigurationSnapshot snapshot);

  Future<void> stop();
}
