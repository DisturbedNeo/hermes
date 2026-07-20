// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'context_summary_prompt.dart';

/// @nodoc
class ContextSummaryMapper extends ClassMapperBase<ContextSummary> {
  ContextSummaryMapper._();

  static ContextSummaryMapper? _instance;
  static ContextSummaryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ContextSummaryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ContextSummary';

  static int _$schemaVersion(ContextSummary v) => v.schemaVersion;
  static const Field<ContextSummary, int> _f$schemaVersion = Field(
    'schemaVersion',
    _$schemaVersion,
    key: r'schema_version',
    hook: JsonIntHook(fallback: 1),
  );
  static String _$task(ContextSummary v) => v.task;
  static const Field<ContextSummary, String> _f$task = Field(
    'task',
    _$task,
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static String _$latestUserRequest(ContextSummary v) => v.latestUserRequest;
  static const Field<ContextSummary, String> _f$latestUserRequest = Field(
    'latestUserRequest',
    _$latestUserRequest,
    key: r'latest_user_request',
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static List<String> _$decisions(ContextSummary v) => v.decisions;
  static const Field<ContextSummary, List<String>> _f$decisions = Field(
    'decisions',
    _$decisions,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$artifacts(ContextSummary v) => v.artifacts;
  static const Field<ContextSummary, List<String>> _f$artifacts = Field(
    'artifacts',
    _$artifacts,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$constraints(ContextSummary v) => v.constraints;
  static const Field<ContextSummary, List<String>> _f$constraints = Field(
    'constraints',
    _$constraints,
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static String _$currentState(ContextSummary v) => v.currentState;
  static const Field<ContextSummary, String> _f$currentState = Field(
    'currentState',
    _$currentState,
    key: r'current_state',
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static List<String> _$openQuestions(ContextSummary v) => v.openQuestions;
  static const Field<ContextSummary, List<String>> _f$openQuestions = Field(
    'openQuestions',
    _$openQuestions,
    key: r'open_questions',
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static List<String> _$recentFailures(ContextSummary v) => v.recentFailures;
  static const Field<ContextSummary, List<String>> _f$recentFailures = Field(
    'recentFailures',
    _$recentFailures,
    key: r'recent_failures',
    opt: true,
    def: const [],
    hook: JsonStringListHook(),
  );
  static String? _$rawText(ContextSummary v) => v.rawText;
  static const Field<ContextSummary, String> _f$rawText = Field(
    'rawText',
    _$rawText,
    opt: true,
  );

  @override
  final MappableFields<ContextSummary> fields = const {
    #schemaVersion: _f$schemaVersion,
    #task: _f$task,
    #latestUserRequest: _f$latestUserRequest,
    #decisions: _f$decisions,
    #artifacts: _f$artifacts,
    #constraints: _f$constraints,
    #currentState: _f$currentState,
    #openQuestions: _f$openQuestions,
    #recentFailures: _f$recentFailures,
    #rawText: _f$rawText,
  };

  static ContextSummary _instantiate(DecodingData data) {
    return ContextSummary(
      schemaVersion: data.dec(_f$schemaVersion),
      task: data.dec(_f$task),
      latestUserRequest: data.dec(_f$latestUserRequest),
      decisions: data.dec(_f$decisions),
      artifacts: data.dec(_f$artifacts),
      constraints: data.dec(_f$constraints),
      currentState: data.dec(_f$currentState),
      openQuestions: data.dec(_f$openQuestions),
      recentFailures: data.dec(_f$recentFailures),
      rawText: data.dec(_f$rawText),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ContextSummary fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ContextSummary>(map);
  }

  static ContextSummary fromJson(String json) {
    return ensureInitialized().decodeJson<ContextSummary>(json);
  }
}

/// @nodoc
mixin ContextSummaryMappable {}

