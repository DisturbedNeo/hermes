import 'package:hermes/core/models/job.dart';
import 'package:path/path.dart' as path;

class JobSpecValidator {
  const JobSpecValidator();

  void throwIfInvalid(JobSpec spec) {
    final issues = validate(spec);
    if (issues.isEmpty) return;
    throw FormatException('Invalid JobSpec: ${issues.join('; ')}');
  }

  List<String> validate(JobSpec spec) {
    final issues = <String>[];
    if (spec.version != 1) {
      issues.add('version must be 1');
    }
    if (spec.id.trim().isEmpty) {
      issues.add('job id is required');
    }
    if (spec.taskBriefId.trim().isEmpty) {
      issues.add('taskBriefId is required');
    }
    if (spec.title.trim().isEmpty) {
      issues.add('job title is required');
    }
    if (spec.phases.isEmpty) {
      issues.add('at least one phase is required');
    }

    final seenPhaseIds = <String>{};
    for (final phase in spec.phases) {
      final phaseLabel = phase.id.trim().isEmpty ? '<empty>' : phase.id;
      if (phase.id.trim().isEmpty) {
        issues.add('phase id is required');
      } else if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(phase.id)) {
        issues.add('phase "$phaseLabel" id must use letters, numbers, _ or -');
      } else if (!seenPhaseIds.add(phase.id)) {
        issues.add('phase id "$phaseLabel" is duplicated');
      }
      if (phase.title.trim().isEmpty) {
        issues.add('phase "$phaseLabel" title is required');
      }
      if (phase.objective.trim().isEmpty) {
        issues.add('phase "$phaseLabel" objective is required');
      }
      if (phase.completionCriteria.isEmpty) {
        issues.add('phase "$phaseLabel" needs completion criteria');
      }
      if (phase.expectedOutputs.isEmpty) {
        issues.add('phase "$phaseLabel" needs at least one expected output');
      }
      for (final input in phase.inputs) {
        if (!isSafeWorkspaceRelativePath(input.path)) {
          issues.add(
            'phase "$phaseLabel" input path is unsafe or empty: ${input.path}',
          );
        }
      }
      for (final output in phase.expectedOutputs) {
        if (!isSafeWorkspaceRelativePath(output.path)) {
          issues.add(
            'phase "$phaseLabel" output path is unsafe or empty: ${output.path}',
          );
        }
      }
      final validation = phase.validation;
      if (validation != null) {
        for (final requiredPath in validation.mustExist) {
          if (!isSafeWorkspaceRelativePath(requiredPath)) {
            issues.add(
              'phase "$phaseLabel" mustExist path is unsafe or empty: $requiredPath',
            );
          }
        }
        for (final protectedPath in validation.mustNotModify) {
          if (!isSafeWorkspaceRelativePath(protectedPath)) {
            issues.add(
              'phase "$phaseLabel" mustNotModify path is unsafe or empty: $protectedPath',
            );
          }
        }
        for (final pattern in [
          ...validation.requiredPatterns,
          ...validation.forbiddenPatterns,
        ]) {
          final error = regexError(pattern);
          if (error != null) {
            issues.add(
              'phase "$phaseLabel" validation regex is invalid: $pattern ($error)',
            );
          }
        }
      }
    }
    return issues;
  }

  bool isSafeWorkspaceRelativePath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        path.isAbsolute(trimmed) ||
        path.windows.isAbsolute(trimmed)) {
      return false;
    }

    final normalised = path.posix.normalize(trimmed.replaceAll('\\', '/'));
    return normalised != '..' &&
        !normalised.startsWith('../') &&
        normalised != '.';
  }

  String? regexError(String pattern) {
    try {
      RegExp(pattern, multiLine: true);
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
