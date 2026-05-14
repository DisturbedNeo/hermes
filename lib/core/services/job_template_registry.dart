import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/services/prompt_library_seed_data.dart';

class BuiltInJobTemplateIds {
  const BuiltInJobTemplateIds._();

  static const String codebaseAudit = 'codebase_audit';
  static const String novelPlanningPack = 'novel_planning_pack';
}

class JobTemplateRegistry {
  const JobTemplateRegistry();

  List<JobTemplate> get templates => BuiltInJobTemplates.all;

  JobTemplate? byId(String id) {
    for (final template in templates) {
      if (template.id == id) return template;
    }
    return null;
  }

  JobTemplate? selectTemplate(TaskBrief brief) {
    final text = '${brief.title}\n${brief.objective}\n${brief.originalPrompt}'
        .toLowerCase();
    if (_looksLikeNovelPlanning(text)) {
      return byId(BuiltInJobTemplateIds.novelPlanningPack);
    }
    if (_looksLikeCodebaseAudit(text) ||
        brief.domain == JobDomain.development) {
      return byId(BuiltInJobTemplateIds.codebaseAudit);
    }
    return null;
  }

  List<Map<String, dynamic>> summaries(String jobId) {
    return [
      for (final template in templates)
        {
          'id': template.id,
          'name': template.name,
          'domain': template.domain.wire,
          'description': template.description,
          'defaultAutonomy': template.defaultAutonomy.wire,
          'defaultConstraints': template.defaultConstraints,
          'defaultSuccessCriteria': template.defaultSuccessCriteria,
          'recommendedPromptModules': template.recommendedPromptModules,
          'phaseIds': [for (final phase in template.phases) phase.id],
          'phases': [
            for (final phase in template.phases)
              {
                'id': phase.id,
                'title': phase.title,
                'objective': phase.objective,
                'expectedOutputs': [
                  for (final output in phase.expectedOutputs)
                    {
                      ...output.toJson(),
                      'path': _replaceJobId(output.path, jobId),
                    },
                ],
              },
          ],
        },
    ];
  }

  bool _looksLikeCodebaseAudit(String text) {
    return RegExp(
      r'\b(audit|analyse this codebase|analyze this codebase|review this repo|major issues|critical issues)\b',
    ).hasMatch(text);
  }

  bool _looksLikeNovelPlanning(String text) {
    return RegExp(
      r'\b(novel|story|chapter outline|characters|worldbuilding|plot spine)\b',
    ).hasMatch(text);
  }

  String _replaceJobId(String value, String jobId) {
    return value.replaceAll('{{job_id}}', jobId);
  }
}

class BuiltInJobTemplates {
  const BuiltInJobTemplates._();

  static const List<JobTemplate> all = [codebaseAudit, novelPlanningPack];

  static const JobTemplate codebaseAudit = JobTemplate(
    id: BuiltInJobTemplateIds.codebaseAudit,
    name: 'Codebase Audit',
    domain: JobDomain.development,
    description:
        'Analyse a codebase for reliability, security, architecture, and maintainability issues.',
    defaultAutonomy: AutonomyLevel.checkpointed,
    defaultConstraints: [
      'Do not modify source files.',
      'Prefer evidence from actual files over speculation.',
      'Do not run destructive commands.',
      'Do not label issues critical without explicit evidence.',
    ],
    defaultSuccessCriteria: [
      'Produce a structured audit report.',
      'Include severity, evidence, impact, confidence, and suggested fix for each finding.',
      'Separate confirmed issues from speculative improvements.',
    ],
    recommendedPromptModules: [
      PromptLibrarySeedIds.codingCore,
      PromptLibrarySeedIds.codingTesting,
      PromptLibrarySeedIds.codingSecurityReview,
      PromptLibrarySeedIds.universalStructuredOutput,
      PromptLibrarySeedIds.universalHighCertaintyOnly,
    ],
    phases: [
      JobPhase(
        id: 'repo_map',
        title: 'Map repository',
        objective:
            'Identify project structure, entry points, tooling, and major subsystems.',
        status: PhaseStatus.pending,
        inputs: [],
        expectedOutputs: [
          PhaseOutput(
            path: '.agent/jobs/{{job_id}}/repo-map.md',
            required: true,
            format: ArtifactFormat.markdown,
          ),
        ],
        allowedTools: ['list_directory', 'read_file', 'search_files'],
        terminalPolicy: TerminalPolicy.readonly,
        completionCriteria: [
          'Identifies project type and framework.',
          'Identifies entry points.',
          'Identifies build and test tooling.',
          'Lists major directories and their roles.',
        ],
        review: ReviewPolicy(required: true, reviewer: ReviewerType.hybrid),
        humanCheckpoint: false,
        retryPolicy: RetryPolicy(),
      ),
      JobPhase(
        id: 'risk_scan',
        title: 'Scan high-risk areas',
        objective:
            'Inspect likely high-risk files and produce preliminary findings.',
        status: PhaseStatus.pending,
        inputs: [
          PhaseInput(
            path: '.agent/jobs/{{job_id}}/repo-map.md',
            required: true,
          ),
        ],
        expectedOutputs: [
          PhaseOutput(
            path: '.agent/jobs/{{job_id}}/preliminary-findings.md',
            required: true,
            format: ArtifactFormat.markdown,
          ),
        ],
        allowedTools: ['list_directory', 'read_file', 'search_files'],
        terminalPolicy: TerminalPolicy.readonly,
        completionCriteria: [
          'Each finding includes affected file, evidence, impact, severity, and confidence.',
          'Speculative concerns are clearly marked speculative.',
          'Critical findings include severity justification.',
        ],
        review: ReviewPolicy(required: true, reviewer: ReviewerType.hybrid),
        humanCheckpoint: false,
        retryPolicy: RetryPolicy(),
      ),
      JobPhase(
        id: 'final_report',
        title: 'Produce final audit report',
        objective:
            'Convert preliminary findings into a prioritized audit report.',
        status: PhaseStatus.pending,
        inputs: [
          PhaseInput(
            path: '.agent/jobs/{{job_id}}/preliminary-findings.md',
            required: true,
          ),
        ],
        expectedOutputs: [
          PhaseOutput(
            path: 'audit-report.md',
            required: true,
            format: ArtifactFormat.markdown,
          ),
        ],
        allowedTools: ['read_file', 'write_file'],
        terminalPolicy: TerminalPolicy.none,
        completionCriteria: [
          'Includes executive summary.',
          'Includes prioritized findings.',
          'Separates critical, high, medium, low, and observation items.',
          'Includes recommended next actions.',
        ],
        review: ReviewPolicy(required: true, reviewer: ReviewerType.hybrid),
        humanCheckpoint: true,
        retryPolicy: RetryPolicy(),
      ),
    ],
  );

  static const JobTemplate novelPlanningPack = JobTemplate(
    id: BuiltInJobTemplateIds.novelPlanningPack,
    name: 'Novel Planning Pack',
    domain: JobDomain.creativeWriting,
    description: 'Create a coherent planning package for a novel.',
    defaultAutonomy: AutonomyLevel.automatic,
    defaultConstraints: [
      'Avoid generic AI-sounding prose.',
      'Prefer specific, concrete details.',
      'Maintain continuity across artifacts.',
      'Do not draft full chapters unless explicitly requested.',
    ],
    defaultSuccessCriteria: [
      'Produce a strong pitch.',
      'Define major characters with motivations and arcs.',
      'Define setting, conflict, and major story logic.',
      'Produce a plot spine and chapter outline.',
      'Include continuity notes.',
    ],
    recommendedPromptModules: [
      PromptLibrarySeedIds.creativeWritingCore,
      PromptLibrarySeedIds.creativeWorldbuilding,
      PromptLibrarySeedIds.creativeDevelopmentalEditing,
      PromptLibrarySeedIds.universalStructuredOutput,
    ],
    phases: [
      JobPhase(
        id: 'premise',
        title: 'Refine premise',
        objective: 'Turn the initial idea into a focused story premise.',
        status: PhaseStatus.pending,
        inputs: [],
        expectedOutputs: [
          PhaseOutput(
            path: 'premise.md',
            required: true,
            format: ArtifactFormat.markdown,
          ),
        ],
        allowedTools: ['read_file'],
        terminalPolicy: TerminalPolicy.none,
        completionCriteria: [
          'Defines genre, tone, protagonist, central conflict, and story promise.',
        ],
        review: ReviewPolicy(required: true, reviewer: ReviewerType.model),
        humanCheckpoint: false,
        retryPolicy: RetryPolicy(),
      ),
      JobPhase(
        id: 'pitch',
        title: 'Create pitch',
        objective: 'Produce a concise pitch and expanded story summary.',
        status: PhaseStatus.pending,
        inputs: [PhaseInput(path: 'premise.md', required: true)],
        expectedOutputs: [
          PhaseOutput(
            path: 'pitch.md',
            required: true,
            format: ArtifactFormat.markdown,
          ),
        ],
        allowedTools: ['read_file'],
        terminalPolicy: TerminalPolicy.none,
        completionCriteria: [
          'Includes logline.',
          'Includes one-page summary.',
          'Establishes tone and hook.',
        ],
        review: ReviewPolicy(required: true, reviewer: ReviewerType.model),
        humanCheckpoint: false,
        retryPolicy: RetryPolicy(),
      ),
      JobPhase(
        id: 'characters',
        title: 'Create cast',
        objective: 'Define major characters, motivations, conflicts, and arcs.',
        status: PhaseStatus.pending,
        inputs: [PhaseInput(path: 'pitch.md', required: true)],
        expectedOutputs: [
          PhaseOutput(
            path: 'characters.md',
            required: true,
            format: ArtifactFormat.markdown,
          ),
        ],
        allowedTools: ['read_file'],
        terminalPolicy: TerminalPolicy.none,
        completionCriteria: [
          'Defines protagonist, antagonist, major allies, and major foils.',
          'Includes goals, fears, contradictions, and arcs.',
        ],
        review: ReviewPolicy(required: true, reviewer: ReviewerType.model),
        humanCheckpoint: false,
        retryPolicy: RetryPolicy(),
      ),
      JobPhase(
        id: 'worldbuilding',
        title: 'Create worldbuilding',
        objective:
            'Define the setting, factions, rules, constraints, and story-relevant history.',
        status: PhaseStatus.pending,
        inputs: [
          PhaseInput(path: 'pitch.md', required: true),
          PhaseInput(path: 'characters.md', required: true),
        ],
        expectedOutputs: [
          PhaseOutput(
            path: 'worldbuilding.md',
            required: true,
            format: ArtifactFormat.markdown,
          ),
        ],
        allowedTools: ['read_file'],
        terminalPolicy: TerminalPolicy.none,
        completionCriteria: [
          'Defines key locations, factions, rules, and constraints.',
          'Avoids generic placeholder worldbuilding.',
        ],
        review: ReviewPolicy(required: true, reviewer: ReviewerType.model),
        humanCheckpoint: false,
        retryPolicy: RetryPolicy(),
      ),
      JobPhase(
        id: 'plot',
        title: 'Create plot spine',
        objective: 'Produce a coherent beginning, middle, and ending.',
        status: PhaseStatus.pending,
        inputs: [
          PhaseInput(path: 'pitch.md', required: true),
          PhaseInput(path: 'characters.md', required: true),
          PhaseInput(path: 'worldbuilding.md', required: true),
        ],
        expectedOutputs: [
          PhaseOutput(
            path: 'plot.md',
            required: true,
            format: ArtifactFormat.markdown,
          ),
        ],
        allowedTools: ['read_file'],
        terminalPolicy: TerminalPolicy.none,
        completionCriteria: [
          'Includes inciting incident, midpoint, crisis, climax, and resolution.',
          'Character arcs affect plot events.',
        ],
        review: ReviewPolicy(required: true, reviewer: ReviewerType.model),
        humanCheckpoint: false,
        retryPolicy: RetryPolicy(),
      ),
      JobPhase(
        id: 'chapter_outline',
        title: 'Create chapter outline',
        objective: 'Convert the plot spine into a chapter-by-chapter outline.',
        status: PhaseStatus.pending,
        inputs: [PhaseInput(path: 'plot.md', required: true)],
        expectedOutputs: [
          PhaseOutput(
            path: 'chapter-outline.md',
            required: true,
            format: ArtifactFormat.markdown,
          ),
        ],
        allowedTools: ['read_file'],
        terminalPolicy: TerminalPolicy.none,
        completionCriteria: [
          'Each chapter has purpose, conflict, turning point, and continuity notes.',
        ],
        review: ReviewPolicy(required: true, reviewer: ReviewerType.model),
        humanCheckpoint: false,
        retryPolicy: RetryPolicy(),
      ),
      JobPhase(
        id: 'continuity_review',
        title: 'Continuity review',
        objective:
            'Review the planning package for contradictions, weak causality, and generic choices.',
        status: PhaseStatus.pending,
        inputs: [
          PhaseInput(path: 'pitch.md', required: true),
          PhaseInput(path: 'characters.md', required: true),
          PhaseInput(path: 'worldbuilding.md', required: true),
          PhaseInput(path: 'plot.md', required: true),
          PhaseInput(path: 'chapter-outline.md', required: true),
        ],
        expectedOutputs: [
          PhaseOutput(
            path: 'continuity-notes.md',
            required: true,
            format: ArtifactFormat.markdown,
          ),
        ],
        allowedTools: ['read_file'],
        terminalPolicy: TerminalPolicy.none,
        completionCriteria: [
          'Identifies contradictions.',
          'Identifies weak motivations.',
          'Identifies generic or underdeveloped elements.',
          'Suggests targeted improvements.',
        ],
        review: ReviewPolicy(required: true, reviewer: ReviewerType.model),
        humanCheckpoint: false,
        retryPolicy: RetryPolicy(),
      ),
    ],
  );
}
