import 'package:hermes/core/models/job.dart';

class ModelReviewProfile {
  final String id;
  final String instruction;
  final List<String> criteria;
  final List<String> validatorIds;

  const ModelReviewProfile({
    required this.id,
    required this.instruction,
    required this.criteria,
    required this.validatorIds,
  });
}

class ModelPhaseValidatorProfile {
  final String id;
  final String instruction;
  final List<String> criteria;

  const ModelPhaseValidatorProfile({
    required this.id,
    required this.instruction,
    required this.criteria,
  });
}

class BuiltInModelValidators {
  const BuiltInModelValidators._();

  static const auditEvidence = ModelPhaseValidatorProfile(
    id: 'AuditEvidenceReview',
    instruction: '''
Use the AuditEvidenceReview validator.
Focus on evidence quality, confidence, and whether every finding is supported by produced artifacts or recorded tool activity.
Do not pass unsupported critical or high-severity claims.
Speculative concerns must be labelled as speculative and should not be treated as confirmed findings.
''',
    criteria: [
      'Every finding has concrete evidence from an artifact, file reference, or recorded action.',
      'Confirmed issues are separated from speculative improvements.',
      'Unsupported critical or high-severity claims are rejected.',
    ],
  );

  static const severityCalibration = ModelPhaseValidatorProfile(
    id: 'SeverityCalibrationReview',
    instruction: '''
Use the SeverityCalibrationReview validator.
Focus on severity labels, impact claims, confidence, and whether the output reserves critical/high severity for issues with explicit evidence.
Do not allow severity inflation, but do not downgrade real high-impact issues without a reason.
''',
    criteria: [
      'Critical severity is used only for plausible data loss, security compromise, complete workflow failure, unrecoverable crash, or severe primary-function breakage.',
      'High severity has clear user, release, security, reliability, or maintainability impact.',
      'Medium, low, and observation labels are used for limited-scope, speculative, or minor concerns.',
      'Each severe finding includes impact and confidence.',
    ],
  );

  static const implementationPlan = ModelPhaseValidatorProfile(
    id: 'ImplementationPlanReview',
    instruction: '''
Use the ImplementationPlanReview validator.
Focus on engineering correctness, phase boundaries, mutation risk, compatibility, and whether the output is sufficient for the next implementation or verification step.
Reject plans or outputs that hand-wave risky edits, ignore constraints, or omit validation.
''',
    criteria: [
      'The output preserves the task objective and declared constraints.',
      'Implementation or refactor steps are concrete enough to execute safely.',
      'Risky file mutations, migrations, and terminal use are called out before they happen.',
      'Verification steps are appropriate for the affected code paths.',
    ],
  );

  static const planCompleteness = ModelPhaseValidatorProfile(
    id: 'PlanCompletenessReview',
    instruction: '''
Use the PlanCompletenessReview validator.
Focus on whether the artifact is specific, complete enough for the next phase, and free of vague placeholder work.
Do not require unnecessary detail, but fail outputs that cannot guide the next phase.
''',
    criteria: [
      'The phase objective is directly addressed.',
      'The output contains the expected decisions, structure, and next-step inputs.',
      'Ambiguities that would block later work are surfaced as questions or assumptions.',
      'The output avoids filler and generic placeholders.',
    ],
  );

  static const fictionContinuity = ModelPhaseValidatorProfile(
    id: 'FictionContinuityReview',
    instruction: '''
Use the FictionContinuityReview validator.
Focus on continuity, causal logic, character motivation, and whether later story artifacts can rely on the output.
Do not fail merely because of taste; fail contradictions, weak causality, or generic placeholders that break planning.
''',
    criteria: [
      'Character goals, fears, contradictions, and arcs remain consistent.',
      'Plot events follow clear cause and effect.',
      'Worldbuilding rules and constraints are not contradicted.',
      'Chapter or plot beats include enough continuity notes for later phases.',
    ],
  );

  static const styleQuality = ModelPhaseValidatorProfile(
    id: 'StyleQualityReview',
    instruction: '''
Use the StyleQualityReview validator.
Focus on specificity, voice, genre fit, and whether prose choices avoid generic AI-sounding placeholders.
Do not enforce personal taste; evaluate against the phase objective and declared creative constraints.
''',
    criteria: [
      'The output uses specific, concrete story details.',
      'Tone and genre promise are coherent.',
      'The prose avoids generic placeholders and padded abstractions.',
      'The artifact is usable by later planning phases.',
    ],
  );

  static const general = ModelPhaseValidatorProfile(
    id: 'GeneralModelReview',
    instruction: '''
Use the GeneralModelReview validator.
Evaluate the phase strictly against objective, constraints, completion criteria, and readiness for the next phase.
''',
    criteria: [
      'The phase objective is satisfied.',
      'Completion criteria are met.',
      'Constraints were followed.',
      'The output supports the next phase.',
    ],
  );

  static ModelReviewProfile select({
    required TaskBrief taskBrief,
    required JobSpec jobSpec,
    required JobPhase phase,
  }) {
    final domain = jobSpec.domain == JobDomain.unknown
        ? taskBrief.domain
        : jobSpec.domain;
    final haystack =
        '${jobSpec.title} ${taskBrief.objective} ${phase.id} ${phase.title} ${phase.objective} ${phase.expectedOutputs.map((output) => output.path).join(' ')}'
            .toLowerCase();
    final phaseWrites =
        phase.allowedTools.contains('write_file') ||
        phase.allowedTools.contains('patch_file') ||
        phase.terminalPolicy == TerminalPolicy.workspaceMutating ||
        phase.terminalPolicy == TerminalPolicy.unrestrictedWorkspace;

    if (domain == JobDomain.creativeWriting) {
      if (_containsAny(haystack, const [
        'continuity',
        'chapter',
        'outline',
        'plot',
        'character',
        'world',
        'cast',
      ])) {
        return combine(const [fictionContinuity, styleQuality]);
      }
      return combine(const [styleQuality]);
    }

    if (domain == JobDomain.development) {
      if (_containsAny(haystack, const [
        'audit',
        'finding',
        'findings',
        'risk',
        'severity',
        'evidence',
        'report',
        'scan',
      ])) {
        return combine(const [auditEvidence, severityCalibration]);
      }
      if (phaseWrites ||
          _containsAny(haystack, const [
            'implement',
            'implementation',
            'refactor',
            'migration',
            'architecture',
            'fix',
          ])) {
        return combine(const [implementationPlan]);
      }
    }

    if (_containsAny(haystack, const [
      'plan',
      'planner',
      'outline',
      'spec',
      'design',
      'brief',
    ])) {
      return combine(const [planCompleteness]);
    }

    return combine(const [general]);
  }

  static ModelReviewProfile combine(
    List<ModelPhaseValidatorProfile> validators,
  ) {
    final selected = validators.isEmpty ? const [general] : validators;
    final ids = selected.map((validator) => validator.id).toList();
    final criteria = <String>[
      for (final validator in selected)
        for (final criterion in validator.criteria)
          '[${validator.id}] $criterion',
    ];

    return ModelReviewProfile(
      id: ids.join('+'),
      validatorIds: ids,
      instruction:
          '''
Run these model validators: ${ids.join(', ')}.

${selected.map((validator) => validator.instruction.trim()).join('\n\n')}
''',
      criteria: criteria,
    );
  }

  static bool _containsAny(String haystack, List<String> needles) {
    for (final needle in needles) {
      if (haystack.contains(needle)) return true;
    }
    return false;
  }
}
