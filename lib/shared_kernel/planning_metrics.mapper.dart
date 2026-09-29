// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'planning_metrics.dart';

/// @nodoc
class PlanningMetricsMapper extends ClassMapperBase<PlanningMetrics> {
  PlanningMetricsMapper._();

  static PlanningMetricsMapper? _instance;
  static PlanningMetricsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PlanningMetricsMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PlanningMetrics';

  static int _$planningCalls(PlanningMetrics v) => v.planningCalls;
  static const Field<PlanningMetrics, int> _f$planningCalls = Field(
    'planningCalls',
    _$planningCalls,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$promptTokenEstimate(PlanningMetrics v) => v.promptTokenEstimate;
  static const Field<PlanningMetrics, int> _f$promptTokenEstimate = Field(
    'promptTokenEstimate',
    _$promptTokenEstimate,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$toolResultTokenEstimate(PlanningMetrics v) =>
      v.toolResultTokenEstimate;
  static const Field<PlanningMetrics, int> _f$toolResultTokenEstimate = Field(
    'toolResultTokenEstimate',
    _$toolResultTokenEstimate,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$planningCommandCount(PlanningMetrics v) =>
      v.planningCommandCount;
  static const Field<PlanningMetrics, int> _f$planningCommandCount = Field(
    'planningCommandCount',
    _$planningCommandCount,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$invalidCommandCount(PlanningMetrics v) => v.invalidCommandCount;
  static const Field<PlanningMetrics, int> _f$invalidCommandCount = Field(
    'invalidCommandCount',
    _$invalidCommandCount,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$fullPlanRepairCount(PlanningMetrics v) => v.fullPlanRepairCount;
  static const Field<PlanningMetrics, int> _f$fullPlanRepairCount = Field(
    'fullPlanRepairCount',
    _$fullPlanRepairCount,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$validationBlockerCount(PlanningMetrics v) =>
      v.validationBlockerCount;
  static const Field<PlanningMetrics, int> _f$validationBlockerCount = Field(
    'validationBlockerCount',
    _$validationBlockerCount,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$recoveryAttempts(PlanningMetrics v) => v.recoveryAttempts;
  static const Field<PlanningMetrics, int> _f$recoveryAttempts = Field(
    'recoveryAttempts',
    _$recoveryAttempts,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static int _$recoverySuccesses(PlanningMetrics v) => v.recoverySuccesses;
  static const Field<PlanningMetrics, int> _f$recoverySuccesses = Field(
    'recoverySuccesses',
    _$recoverySuccesses,
    opt: true,
    def: 0,
    hook: JsonIntHook(),
  );
  static DateTime? _$planningStartedAt(PlanningMetrics v) =>
      v.planningStartedAt;
  static const Field<PlanningMetrics, DateTime> _f$planningStartedAt = Field(
    'planningStartedAt',
    _$planningStartedAt,
    opt: true,
    hook: JsonNullableDateHook(),
  );
  static int? _$timeToFirstExecutableMs(PlanningMetrics v) =>
      v.timeToFirstExecutableMs;
  static const Field<PlanningMetrics, int> _f$timeToFirstExecutableMs = Field(
    'timeToFirstExecutableMs',
    _$timeToFirstExecutableMs,
    opt: true,
  );

  @override
  final MappableFields<PlanningMetrics> fields = const {
    #planningCalls: _f$planningCalls,
    #promptTokenEstimate: _f$promptTokenEstimate,
    #toolResultTokenEstimate: _f$toolResultTokenEstimate,
    #planningCommandCount: _f$planningCommandCount,
    #invalidCommandCount: _f$invalidCommandCount,
    #fullPlanRepairCount: _f$fullPlanRepairCount,
    #validationBlockerCount: _f$validationBlockerCount,
    #recoveryAttempts: _f$recoveryAttempts,
    #recoverySuccesses: _f$recoverySuccesses,
    #planningStartedAt: _f$planningStartedAt,
    #timeToFirstExecutableMs: _f$timeToFirstExecutableMs,
  };
  @override
  final bool ignoreNull = true;

  static PlanningMetrics _instantiate(DecodingData data) {
    return PlanningMetrics(
      planningCalls: data.dec(_f$planningCalls),
      promptTokenEstimate: data.dec(_f$promptTokenEstimate),
      toolResultTokenEstimate: data.dec(_f$toolResultTokenEstimate),
      planningCommandCount: data.dec(_f$planningCommandCount),
      invalidCommandCount: data.dec(_f$invalidCommandCount),
      fullPlanRepairCount: data.dec(_f$fullPlanRepairCount),
      validationBlockerCount: data.dec(_f$validationBlockerCount),
      recoveryAttempts: data.dec(_f$recoveryAttempts),
      recoverySuccesses: data.dec(_f$recoverySuccesses),
      planningStartedAt: data.dec(_f$planningStartedAt),
      timeToFirstExecutableMs: data.dec(_f$timeToFirstExecutableMs),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PlanningMetrics fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PlanningMetrics>(map);
  }

  static PlanningMetrics fromJson(String json) {
    return ensureInitialized().decodeJson<PlanningMetrics>(json);
  }
}

/// @nodoc
mixin PlanningMetricsMappable {
  String toJson() {
    return PlanningMetricsMapper.ensureInitialized()
        .encodeJson<PlanningMetrics>(this as PlanningMetrics);
  }

  Map<String, dynamic> toMap() {
    return PlanningMetricsMapper.ensureInitialized().encodeMap<PlanningMetrics>(
      this as PlanningMetrics,
    );
  }
}

