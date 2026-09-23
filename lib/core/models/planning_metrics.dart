import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/helpers/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/core/serialization/json_hooks.dart';

part 'planning_metrics.mapper.dart';

/// Durable, privacy-preserving measurements for the planning protocol.
///
/// This intentionally stores counts and token estimates only. Prompts,
/// tool arguments, file contents, and model output are not retained here.
@MappableClass(ignoreNull: true)
class PlanningMetrics with PlanningMetricsMappable {
  @MappableField(hook: JsonIntHook())
  final int planningCalls;
  @MappableField(hook: JsonIntHook())
  final int promptTokenEstimate;
  @MappableField(hook: JsonIntHook())
  final int toolResultTokenEstimate;
  @MappableField(hook: JsonIntHook())
  final int planningCommandCount;
  @MappableField(hook: JsonIntHook())
  final int invalidCommandCount;
  @MappableField(hook: JsonIntHook())
  final int fullPlanRepairCount;
  @MappableField(hook: JsonIntHook())
  final int validationBlockerCount;
  @MappableField(hook: JsonIntHook())
  final int recoveryAttempts;
  @MappableField(hook: JsonIntHook())
  final int recoverySuccesses;
  @MappableField(hook: JsonNullableDateHook())
  final DateTime? planningStartedAt;
  final int? timeToFirstExecutableMs;

  const PlanningMetrics({
    this.planningCalls = 0,
    this.promptTokenEstimate = 0,
    this.toolResultTokenEstimate = 0,
    this.planningCommandCount = 0,
    this.invalidCommandCount = 0,
    this.fullPlanRepairCount = 0,
    this.validationBlockerCount = 0,
    this.recoveryAttempts = 0,
    this.recoverySuccesses = 0,
    this.planningStartedAt,
    this.timeToFirstExecutableMs,
  });

  double get invalidCommandRate => planningCommandCount == 0
      ? 0
      : invalidCommandCount / planningCommandCount;

  double get fullPlanRepairRate =>
      planningCalls == 0 ? 0 : fullPlanRepairCount / planningCalls;

  double get recoverySuccessRate =>
      recoveryAttempts == 0 ? 0 : recoverySuccesses / recoveryAttempts;

  PlanningMetrics copyWith({
    int? planningCalls,
    int? promptTokenEstimate,
    int? toolResultTokenEstimate,
    int? planningCommandCount,
    int? invalidCommandCount,
    int? fullPlanRepairCount,
    int? validationBlockerCount,
    int? recoveryAttempts,
    int? recoverySuccesses,
    Object? planningStartedAt = kSentinel,
    Object? timeToFirstExecutableMs = kSentinel,
  }) => PlanningMetrics(
    planningCalls: planningCalls ?? this.planningCalls,
    promptTokenEstimate: promptTokenEstimate ?? this.promptTokenEstimate,
    toolResultTokenEstimate:
        toolResultTokenEstimate ?? this.toolResultTokenEstimate,
    planningCommandCount: planningCommandCount ?? this.planningCommandCount,
    invalidCommandCount: invalidCommandCount ?? this.invalidCommandCount,
    fullPlanRepairCount: fullPlanRepairCount ?? this.fullPlanRepairCount,
    validationBlockerCount:
        validationBlockerCount ?? this.validationBlockerCount,
    recoveryAttempts: recoveryAttempts ?? this.recoveryAttempts,
    recoverySuccesses: recoverySuccesses ?? this.recoverySuccesses,
    planningStartedAt: resolve(planningStartedAt, this.planningStartedAt),
    timeToFirstExecutableMs: resolve(
      timeToFirstExecutableMs,
      this.timeToFirstExecutableMs,
    ),
  );

  PlanningMetrics add(PlanningMetrics other) => copyWith(
    planningCalls: planningCalls + other.planningCalls,
    promptTokenEstimate: promptTokenEstimate + other.promptTokenEstimate,
    toolResultTokenEstimate:
        toolResultTokenEstimate + other.toolResultTokenEstimate,
    planningCommandCount: planningCommandCount + other.planningCommandCount,
    invalidCommandCount: invalidCommandCount + other.invalidCommandCount,
    fullPlanRepairCount: fullPlanRepairCount + other.fullPlanRepairCount,
    validationBlockerCount:
        validationBlockerCount + other.validationBlockerCount,
    recoveryAttempts: recoveryAttempts + other.recoveryAttempts,
    recoverySuccesses: recoverySuccesses + other.recoverySuccesses,
  );
}
