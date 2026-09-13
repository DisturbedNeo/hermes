/// Selects which model-facing planning protocol a service may use.
///
/// [automatic] is the rollout mode: Hermes prefers incremental planning
/// commands and accepts a legacy finalizer only when an older adapter returns
/// one. [incremental] is strict and never asks the model for a replacement
/// document. [legacy] exists as an explicit rollback for older model adapters;
/// it is not used by the normal application default.
enum PlanningProtocolMode { automatic, incremental, legacy }

/// Optional capability implemented by model-backed planning adapters that can
/// switch between the rollout and compatibility protocols at runtime.
abstract interface class PlanningProtocolConfigurable {
  PlanningProtocolMode get planningProtocolMode;

  set planningProtocolMode(PlanningProtocolMode value);
}

extension PlanningProtocolModeWire on PlanningProtocolMode {
  String get wire => name;

  String get label => switch (this) {
    PlanningProtocolMode.automatic => 'Automatic rollout',
    PlanningProtocolMode.incremental => 'Incremental commands',
    PlanningProtocolMode.legacy => 'Legacy finalizer (compatibility)',
  };

  static PlanningProtocolMode parse(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    return switch (raw) {
      'incremental' || 'commands' => PlanningProtocolMode.incremental,
      'legacy' || 'finalizer' => PlanningProtocolMode.legacy,
      _ => PlanningProtocolMode.automatic,
    };
  }
}
