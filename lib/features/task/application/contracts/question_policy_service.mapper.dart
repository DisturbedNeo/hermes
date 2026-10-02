// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'question_policy_service.dart';

/// @nodoc

class QuestionKindMapper extends EnumMapper<QuestionKind> {
  QuestionKindMapper._();

  static QuestionKindMapper? _instance;
  static QuestionKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = QuestionKindMapper._());
    }
    return _instance!;
  }

  static QuestionKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  QuestionKind decode(dynamic value) {
    switch (value) {
      case r'blocking':
        return QuestionKind.blocking;
      case r'preference':
        return QuestionKind.preference;
      case r'advisory':
        return QuestionKind.advisory;
      default:
        return QuestionKind.values[0];
    }
  }

  @override
  dynamic encode(QuestionKind self) {
    switch (self) {
      case QuestionKind.blocking:
        return r'blocking';
      case QuestionKind.preference:
        return r'preference';
      case QuestionKind.advisory:
        return r'advisory';
    }
  }
}

/// @nodoc

extension QuestionKindMapperExtension on QuestionKind {
  String toValue() {
    QuestionKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<QuestionKind>(this) as String;
  }
}

/// @nodoc
class AgentQuestionMapper extends ClassMapperBase<AgentQuestion> {
  AgentQuestionMapper._();

  static AgentQuestionMapper? _instance;
  static AgentQuestionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AgentQuestionMapper._());
      QuestionKindMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AgentQuestion';

  static String _$question(AgentQuestion v) => v.question;
  static const Field<AgentQuestion, String> _f$question = Field(
    'question',
    _$question,
    hook: JsonStringHook(),
  );
  static String _$reason(AgentQuestion v) => v.reason;
  static const Field<AgentQuestion, String> _f$reason = Field(
    'reason',
    _$reason,
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static String _$defaultIfUnanswered(AgentQuestion v) => v.defaultIfUnanswered;
  static const Field<AgentQuestion, String> _f$defaultIfUnanswered = Field(
    'defaultIfUnanswered',
    _$defaultIfUnanswered,
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static String _$riskOfAssuming(AgentQuestion v) => v.riskOfAssuming;
  static const Field<AgentQuestion, String> _f$riskOfAssuming = Field(
    'riskOfAssuming',
    _$riskOfAssuming,
    opt: true,
    def: '',
    hook: JsonStringHook(),
  );
  static QuestionKind _$kind(AgentQuestion v) => v.kind;
  static const Field<AgentQuestion, QuestionKind> _f$kind = Field(
    'kind',
    _$kind,
    opt: true,
    def: QuestionKind.blocking,
  );

  @override
  final MappableFields<AgentQuestion> fields = const {
    #question: _f$question,
    #reason: _f$reason,
    #defaultIfUnanswered: _f$defaultIfUnanswered,
    #riskOfAssuming: _f$riskOfAssuming,
    #kind: _f$kind,
  };

  @override
  final MappingHook hook = const JsonModelHook();
  static AgentQuestion _instantiate(DecodingData data) {
    return AgentQuestion(
      question: data.dec(_f$question),
      reason: data.dec(_f$reason),
      defaultIfUnanswered: data.dec(_f$defaultIfUnanswered),
      riskOfAssuming: data.dec(_f$riskOfAssuming),
      kind: data.dec(_f$kind),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AgentQuestion fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AgentQuestion>(map);
  }

  static AgentQuestion fromJson(String json) {
    return ensureInitialized().decodeJson<AgentQuestion>(json);
  }
}

/// @nodoc
mixin AgentQuestionMappable {}

