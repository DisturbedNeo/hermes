import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/serialization/json_hooks.dart';
import 'package:hermes/core/serialization/model_json.dart';

part 'question_policy_service.mapper.dart';

@MappableEnum(defaultValue: QuestionKind.blocking)
enum QuestionKind { blocking, preference, advisory }

@MappableClass(generateMethods: GenerateMethods.decode, hook: JsonModelHook())
class AgentQuestion with AgentQuestionMappable {
  @MappableField(hook: JsonStringHook())
  final String question;
  @MappableField(hook: JsonStringHook())
  final String reason;
  @MappableField(hook: JsonStringHook())
  final String defaultIfUnanswered;
  @MappableField(hook: JsonStringHook())
  final String riskOfAssuming;
  final QuestionKind kind;

  const AgentQuestion({
    required this.question,
    this.reason = '',
    this.defaultIfUnanswered = '',
    this.riskOfAssuming = '',
    this.kind = QuestionKind.blocking,
  });

  factory AgentQuestion.fromText(String question) {
    return AgentQuestion(question: question);
  }

  static AgentQuestion? parse(Object? value) {
    if (value == null) return null;
    if (value is Map) {
      return ModelJson.decode<AgentQuestion>(value);
    }
    final question = jsonString(value).trim();
    if (question.isEmpty) return null;
    return AgentQuestion.fromText(question);
  }

  String get displayText {
    final parts = [
      question,
      if (reason.trim().isNotEmpty) 'Reason: ${reason.trim()}',
      if (defaultIfUnanswered.trim().isNotEmpty)
        'Default if unanswered: ${defaultIfUnanswered.trim()}',
      if (riskOfAssuming.trim().isNotEmpty)
        'Risk of assuming: ${riskOfAssuming.trim()}',
      if (kind != QuestionKind.blocking) 'Kind: ${kind.name}',
    ];
    return parts.join('\n');
  }

  String get assumptionSummary {
    final defaultText = defaultIfUnanswered.trim().isEmpty
        ? _defaultAssumption(question)
        : defaultIfUnanswered.trim();
    final reasonText = reason.trim().isEmpty
        ? 'The question appears reversible or preference-based.'
        : reason.trim();
    return 'Assumed: $defaultText\nOriginal question: $question\nReason: $reasonText';
  }
}

class QuestionPolicyDecision {
  final AgentQuestion question;
  final bool shouldBlock;
  final String assumption;

  const QuestionPolicyDecision({
    required this.question,
    required this.shouldBlock,
    required this.assumption,
  });
}

class QuestionPolicyService {
  const QuestionPolicyService();

  QuestionPolicyDecision decide({
    required AgentQuestion question,
    required QuestionAutonomy autonomy,
  }) {
    final text = [
      question.question,
      question.reason,
      question.riskOfAssuming,
    ].join(' ').toLowerCase();
    final forcedBlock = _containsAny(text, _alwaysBlockingTerms);
    final lowRisk =
        question.kind == QuestionKind.preference ||
        question.kind == QuestionKind.advisory ||
        _containsAny(text, _lowRiskTerms);
    final hasDefault = question.defaultIfUnanswered.trim().isNotEmpty;
    final highCost = _containsAny(text, _highCostTerms);

    final shouldBlock = switch (autonomy) {
      QuestionAutonomy.conservative => forcedBlock || (!lowRisk && !hasDefault),
      QuestionAutonomy.balanced => forcedBlock || highCost,
      QuestionAutonomy.autonomous => forcedBlock,
    };

    return QuestionPolicyDecision(
      question: question,
      shouldBlock: shouldBlock,
      assumption: question.assumptionSummary,
    );
  }

  static bool _containsAny(String value, List<String> terms) {
    return terms.any(value.contains);
  }
}

const List<String> _alwaysBlockingTerms = [
  'api key',
  'apikey',
  'secret',
  'token',
  'credential',
  'password',
  'login',
  'account',
  'billing',
  'payment',
  'delete',
  'remove all',
  'drop database',
  'destructive',
  'irreversible',
  'legal',
  'license',
  'compliance',
  'privacy',
  'scope',
  'out of scope',
  'business requirement',
  'product requirement',
  'target platform',
  'which platform',
  'approval',
];

const List<String> _highCostTerms = [
  'waste substantial',
  'large rewrite',
  'architectural rewrite',
  'migration',
  'breaking change',
  'cannot proceed',
  'blocked',
];

const List<String> _lowRiskTerms = [
  'prioritise',
  'prioritize',
  'which ui component',
  'which component',
  'start with',
  'order',
  'naming',
  'name',
  'layout',
  'visual',
  'style',
  'color',
  'colour',
  'minor',
  'preference',
  'implementation order',
];

String _defaultAssumption(String question) {
  final lower = question.toLowerCase();
  if (lower.contains('prioritise') ||
      lower.contains('prioritize') ||
      lower.contains('which component') ||
      lower.contains('which ui component')) {
    return 'prioritize the first reasonable component, then continue with the rest.';
  }
  if (lower.contains('order')) {
    return 'use the most natural implementation order based on existing dependencies.';
  }
  if (lower.contains('name') || lower.contains('naming')) {
    return 'choose a clear name consistent with the existing codebase.';
  }
  if (lower.contains('layout') ||
      lower.contains('visual') ||
      lower.contains('style')) {
    return 'follow the existing design patterns in the workspace.';
  }
  return 'make the most useful reversible assumption and continue.';
}
