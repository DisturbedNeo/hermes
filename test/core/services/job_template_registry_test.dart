import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/services/job_system/job_template_registry.dart';

void main() {
  group('JobTemplateRegistry', () {
    test('exposes built-in job templates as structured models', () {
      const registry = JobTemplateRegistry();

      final audit = registry.byId(BuiltInJobTemplateIds.codebaseAudit);
      final novel = registry.byId(BuiltInJobTemplateIds.novelPlanningPack);

      expect(audit, isNotNull);
      expect(audit!.domain, JobDomain.development);
      expect(audit.phases.map((phase) => phase.id), [
        'repo_map',
        'risk_scan',
        'final_report',
      ]);
      expect(audit.defaultConstraints, contains('Do not modify source files.'));

      expect(novel, isNotNull);
      expect(novel!.defaultAutonomy, AutonomyLevel.automatic);
      expect(
        novel.phases.map((phase) => phase.id),
        contains('chapter_outline'),
      );
    });

    test('serializes templates without losing phase metadata', () {
      final template = BuiltInJobTemplates.codebaseAudit;

      final decoded = JobTemplate.fromJson(template.toJson());

      expect(decoded.id, template.id);
      expect(
        decoded.recommendedPromptModules,
        template.recommendedPromptModules,
      );
      expect(decoded.phases.last.humanCheckpoint, isTrue);
      expect(
        decoded.phases.last.expectedOutputs.single.path,
        'audit-report.md',
      );
    });

    test('renders planner summaries with job id placeholders resolved', () {
      const registry = JobTemplateRegistry();

      final summaries = registry.summaries('job_123');
      final audit = summaries.firstWhere(
        (summary) => summary['id'] == BuiltInJobTemplateIds.codebaseAudit,
      );
      final phases = audit['phases'] as List;
      final firstOutput = (phases.first as Map)['expectedOutputs'] as List;

      expect(
        (firstOutput.single as Map)['path'],
        '.agent/jobs/job_123/repo-map.md',
      );
    });
  });
}
