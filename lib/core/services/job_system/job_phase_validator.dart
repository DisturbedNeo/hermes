import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/helpers/regex.dart';
import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/services/terminal_command_classifier.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

enum PhaseValidatorType { deterministic, model }

typedef TerminalCommandClassifierFn = TerminalCommandClass Function(String command);

abstract class PhaseValidator {
  String get id;
  PhaseValidatorType get type;

  Future<List<PhaseValidationResult>> validate(PhaseValidationInput input);
}

class PhaseValidationInput {
  final String workspaceRoot;
  final WorkspaceSandbox sandbox;
  final JobSpec jobSpec;
  final JobState jobState;
  final JobPhase phase;
  final PhaseRun phaseRun;
  final Map<String, String> artifacts;
  final Set<String> allowedTools;
  final TerminalPolicy terminalPolicy;
  final StopPolicy stopPolicy;
  final TerminalCommandClassifierFn classifyCommand;

  const PhaseValidationInput({
    required this.workspaceRoot,
    required this.sandbox,
    required this.jobSpec,
    required this.jobState,
    required this.phase,
    required this.phaseRun,
    required this.artifacts,
    required this.allowedTools,
    required this.terminalPolicy,
    required this.stopPolicy,
    required this.classifyCommand,
  });
}

class PhaseValidationResult {
  final String id;
  final bool passed;
  final String severity;
  final String message;
  final Object? details;

  const PhaseValidationResult({
    required this.id,
    required this.passed,
    required this.severity,
    required this.message,
    this.details,
  });

  DeterministicCheckResult toDeterministicCheck() {
    return DeterministicCheckResult(id: id, passed: passed, message: message);
  }
}

class BuiltInPhaseValidators {
  const BuiltInPhaseValidators._();

  static const List<PhaseValidator> deterministic = [
    FileExistsValidator(),
    NonEmptyFileValidator(),
    JsonParseValidator(),
    YamlParseValidator(),
    AllowedToolValidator(),
    TerminalPolicyValidator(),
    TerminalCommandClassificationValidator(),
    RuntimeBudgetValidator(),
    TerminalCommandBudgetValidator(),
    FilesReadBudgetValidator(),
    NoSourceMutationValidator(),
    RequiredSectionValidator(),
    RequiredPatternValidator(),
    ForbiddenPatternValidator(),
    MustExistValidator(),
    MustNotModifyValidator(),
  ];
}

abstract class DeterministicPhaseValidator implements PhaseValidator {
  const DeterministicPhaseValidator();

  @override
  PhaseValidatorType get type => PhaseValidatorType.deterministic;
}

class FileExistsValidator extends DeterministicPhaseValidator {
  const FileExistsValidator();

  @override
  String get id => 'file_exists';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    final checks = <PhaseValidationResult>[];
    for (final output in input.phase.expectedOutputs.where((o) => o.required)) {
      final exists = await _fileExists(input, output.path);
      checks.add(
        PhaseValidationResult(
          id: 'file_exists:${output.path}',
          passed: exists,
          severity: exists ? 'info' : 'error',
          message: exists
              ? 'Required output exists: ${output.path}'
              : 'Required output is missing: ${output.path}',
        ),
      );
    }
    return checks;
  }
}

class NonEmptyFileValidator extends DeterministicPhaseValidator {
  const NonEmptyFileValidator();

  @override
  String get id => 'non_empty_file';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    final checks = <PhaseValidationResult>[];
    for (final output in input.phase.expectedOutputs.where((o) => o.required)) {
      final content = input.artifacts[output.path];
      final exists = content != null;
      final nonEmpty = exists && content.trim().isNotEmpty;
      if (!exists) continue;
      checks.add(
        PhaseValidationResult(
          id: 'non_empty:${output.path}',
          passed: nonEmpty,
          severity: nonEmpty ? 'info' : 'error',
          message: nonEmpty
              ? 'Required output is non-empty: ${output.path}'
              : 'Required output is empty: ${output.path}',
        ),
      );
    }
    return checks;
  }
}

class JsonParseValidator extends DeterministicPhaseValidator {
  const JsonParseValidator();

  @override
  String get id => 'json_parse';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    return [
      for (final output in input.phase.expectedOutputs)
        if (output.format == ArtifactFormat.json &&
            input.artifacts.containsKey(output.path))
          _result(
            id: 'json_parse:${output.path}',
            passed: _jsonParses(input.artifacts[output.path]!),
            ok: 'JSON output parses: ${output.path}',
            fail: 'JSON output does not parse: ${output.path}',
          ),
    ];
  }
}

class YamlParseValidator extends DeterministicPhaseValidator {
  const YamlParseValidator();

  @override
  String get id => 'yaml_parse';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    return [
      for (final output in input.phase.expectedOutputs)
        if (output.format == ArtifactFormat.yaml &&
            input.artifacts.containsKey(output.path))
          _result(
            id: 'yaml_parse:${output.path}',
            passed: _yamlParsesStructured(input.artifacts[output.path]!),
            ok: 'YAML output looks parseable: ${output.path}',
            fail: 'YAML output does not look parseable: ${output.path}',
          ),
    ];
  }
}

class AllowedToolValidator extends DeterministicPhaseValidator {
  const AllowedToolValidator();

  @override
  String get id => 'allowed_tools';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    final disallowed = input.phaseRun.toolCalls
        .where((call) => !input.allowedTools.contains(call.toolName))
        .map((call) => call.toolName)
        .toSet();
    return [
      PhaseValidationResult(
        id: id,
        passed: disallowed.isEmpty,
        severity: disallowed.isEmpty ? 'info' : 'error',
        message: disallowed.isEmpty
            ? 'All tool calls were phase-allowed.'
            : 'Disallowed tools were called: ${disallowed.join(', ')}',
      ),
    ];
  }
}

class TerminalPolicyValidator extends DeterministicPhaseValidator {
  const TerminalPolicyValidator();

  @override
  String get id => 'terminal_policy';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    if (input.terminalPolicy == TerminalPolicy.none) {
      return [
        PhaseValidationResult(
          id: 'terminal_policy',
          passed: input.phaseRun.terminalCommands.isEmpty,
          severity: input.phaseRun.terminalCommands.isEmpty ? 'info' : 'error',
          message: input.phaseRun.terminalCommands.isEmpty
              ? 'No terminal commands were run.'
              : 'Terminal commands were run despite terminalPolicy none.',
        ),
      ];
    }
    if (input.terminalPolicy != TerminalPolicy.readonly) return const [];

    final mutatingCommands = input.phaseRun.terminalCommands
        .where(
          (command) => TerminalCommandClassifier.isClearlyMutating(
            input.classifyCommand(command),
          ),
        )
        .toList();
    return [
      PhaseValidationResult(
        id: 'terminal_readonly_policy',
        passed: mutatingCommands.isEmpty,
        severity: mutatingCommands.isEmpty ? 'info' : 'error',
        message: mutatingCommands.isEmpty
            ? 'Terminal commands were read-only by classifier.'
            : 'Readonly terminal phase ran non-readonly commands: ${_classedCommands(mutatingCommands, input.classifyCommand)}',
      ),
    ];
  }
}

class TerminalCommandClassificationValidator
    extends DeterministicPhaseValidator {
  const TerminalCommandClassificationValidator();

  @override
  String get id => 'terminal_command_classes';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    if (input.phaseRun.terminalCommands.isEmpty) return const [];
    return [
      PhaseValidationResult(
        id: id,
        passed: true,
        severity: 'info',
        message:
            'Terminal command classes: ${_classedCommands(input.phaseRun.terminalCommands, input.classifyCommand)}',
      ),
    ];
  }
}

class RuntimeBudgetValidator extends DeterministicPhaseValidator {
  const RuntimeBudgetValidator();

  @override
  String get id => 'max_runtime_seconds';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    final maxRuntimeSeconds = input.stopPolicy.maxRuntimeSeconds;
    final completedAt = input.phaseRun.completedAt;
    if (maxRuntimeSeconds == null || completedAt == null) return const [];
    final runtime = completedAt.difference(input.phaseRun.startedAt);
    final maxRuntime = Duration(seconds: maxRuntimeSeconds);
    return [
      PhaseValidationResult(
        id: id,
        passed: runtime <= maxRuntime,
        severity: runtime <= maxRuntime ? 'info' : 'error',
        message:
            'Phase runtime ${'${(runtime.inMilliseconds / 1000).toStringAsFixed(1)} seconds'}/$maxRuntimeSeconds seconds.',
      ),
    ];
  }
}

class TerminalCommandBudgetValidator extends DeterministicPhaseValidator {
  const TerminalCommandBudgetValidator();

  @override
  String get id => 'max_phase_terminal_commands';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    final maxTerminalCommands = input.stopPolicy.maxPhaseTerminalCommands;
    if (maxTerminalCommands == null) return const [];
    return [
      PhaseValidationResult(
        id: id,
        passed: input.phaseRun.terminalCommands.length <= maxTerminalCommands,
        severity: input.phaseRun.terminalCommands.length <= maxTerminalCommands
            ? 'info'
            : 'error',
        message:
            'Phase ran ${input.phaseRun.terminalCommands.length}/$maxTerminalCommands terminal commands.',
      ),
    ];
  }
}

class FilesReadBudgetValidator extends DeterministicPhaseValidator {
  const FilesReadBudgetValidator();

  @override
  String get id => 'max_phase_files_read';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    final maxFilesRead = input.stopPolicy.maxPhaseFilesRead;
    if (maxFilesRead == null) return const [];
    return [
      PhaseValidationResult(
        id: id,
        passed: input.phaseRun.filesRead.length <= maxFilesRead,
        severity: input.phaseRun.filesRead.length <= maxFilesRead
            ? 'info'
            : 'error',
        message:
            'Phase read ${input.phaseRun.filesRead.length}/$maxFilesRead files.',
      ),
    ];
  }
}

class NoSourceMutationValidator extends DeterministicPhaseValidator {
  const NoSourceMutationValidator();

  @override
  String get id => 'no_unexpected_source_mutation';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    final expectedOutputPaths = input.phase.expectedOutputs
        .map((output) => output.path)
        .toSet();
    final unexpectedWrites =
        [...input.phaseRun.filesWritten, ...input.phaseRun.filesPatched]
            .where(
              (filePath) =>
                  !expectedOutputPaths.contains(filePath) &&
                  !filePath.startsWith('.agent/jobs/${input.jobSpec.id}/'),
            )
            .toList();
    final phaseWritesAllowed =
        input.allowedTools.contains('write_file') ||
        input.allowedTools.contains('patch_file');
    final passed = phaseWritesAllowed || unexpectedWrites.isEmpty;
    return [
      PhaseValidationResult(
        id: id,
        passed: passed,
        severity: passed ? 'info' : 'error',
        message: unexpectedWrites.isEmpty
            ? 'No unexpected source mutations were recorded.'
            : 'Unexpected workspace mutations: ${unexpectedWrites.join(', ')}',
      ),
    ];
  }
}

class RequiredSectionValidator extends DeterministicPhaseValidator {
  const RequiredSectionValidator();

  @override
  String get id => 'required_section';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    final validation = input.phase.validation;
    if (validation == null) return const [];
    final combined = _combinedArtifacts(input);
    return [
      for (final section in validation.requiredSections)
        _result(
          id: 'required_section:$section',
          passed: combined.contains(section),
          ok: 'Required section present: $section',
          fail: 'Required section missing: $section',
        ),
    ];
  }
}

class RequiredPatternValidator extends DeterministicPhaseValidator {
  const RequiredPatternValidator();

  @override
  String get id => 'required_pattern';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    final validation = input.phase.validation;
    if (validation == null) return const [];
    final combined = _combinedArtifacts(input);
    return [
      for (final pattern in validation.requiredPatterns)
        _patternResult(
          id: 'required_pattern:$pattern',
          pattern: pattern,
          content: combined,
          expectedMatch: true,
        ),
    ];
  }
}

class ForbiddenPatternValidator extends DeterministicPhaseValidator {
  const ForbiddenPatternValidator();

  @override
  String get id => 'forbidden_pattern';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    final validation = input.phase.validation;
    if (validation == null) return const [];
    final combined = _combinedArtifacts(input);
    return [
      for (final pattern in validation.forbiddenPatterns)
        _patternResult(
          id: 'forbidden_pattern:$pattern',
          pattern: pattern,
          content: combined,
          expectedMatch: false,
        ),
    ];
  }
}

class MustExistValidator extends DeterministicPhaseValidator {
  const MustExistValidator();

  @override
  String get id => 'must_exist';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    final validation = input.phase.validation;
    if (validation == null) return const [];
    final checks = <PhaseValidationResult>[];
    for (final requiredPath in validation.mustExist) {
      final exists = await _pathExists(input, requiredPath);
      checks.add(
        PhaseValidationResult(
          id: 'must_exist:$requiredPath',
          passed: exists,
          severity: exists ? 'info' : 'error',
          message: exists
              ? 'Required workspace path exists: $requiredPath'
              : 'Required workspace path is missing: $requiredPath',
        ),
      );
    }
    return checks;
  }
}

class MustNotModifyValidator extends DeterministicPhaseValidator {
  const MustNotModifyValidator();

  @override
  String get id => 'must_not_modify';

  @override
  Future<List<PhaseValidationResult>> validate(
    PhaseValidationInput input,
  ) async {
    final validation = input.phase.validation;
    if (validation == null) return const [];
    final modifiedPaths = {
      ...input.phaseRun.filesWritten,
      ...input.phaseRun.filesPatched,
    }.toList()..sort();
    return [
      for (final protectedPath in validation.mustNotModify)
        _protectedPathResult(protectedPath, modifiedPaths),
    ];
  }
}

PhaseValidationResult _protectedPathResult(
  String protectedPath,
  List<String> modifiedPaths,
) {
  final modified = modifiedPaths
      .where((filePath) => _pathMatchesConstraint(filePath, protectedPath))
      .toList();
  return PhaseValidationResult(
    id: 'must_not_modify:$protectedPath',
    passed: modified.isEmpty,
    severity: modified.isEmpty ? 'info' : 'error',
    message: modified.isEmpty
        ? 'Protected path was not modified: $protectedPath'
        : 'Protected path was modified: ${modified.join(', ')}',
  );
}

PhaseValidationResult _patternResult({
  required String id,
  required String pattern,
  required String content,
  required bool expectedMatch,
}) {
  final error = regexError(pattern);
  final matched = error == null && regexMatches(pattern, content);
  final passed = error == null && (expectedMatch ? matched : !matched);
  return PhaseValidationResult(
    id: id,
    passed: passed,
    severity: passed ? 'info' : 'error',
    message: error != null
        ? '${expectedMatch ? 'Required' : 'Forbidden'} pattern is invalid: $pattern ($error)'
        : expectedMatch
        ? matched
              ? 'Required pattern matched: $pattern'
              : 'Required pattern missing: $pattern'
        : matched
        ? 'Forbidden pattern matched: $pattern'
        : 'Forbidden pattern absent: $pattern',
  );
}

PhaseValidationResult _result({
  required String id,
  required bool passed,
  required String ok,
  required String fail,
}) {
  return PhaseValidationResult(
    id: id,
    passed: passed,
    severity: passed ? 'info' : 'error',
    message: passed ? ok : fail,
  );
}

String _combinedArtifacts(PhaseValidationInput input) {
  return input.artifacts.values.join('\n\n');
}

Future<bool> _fileExists(
  PhaseValidationInput input,
  String relativePath,
) async {
  final resolved = await _resolveMaybe(input, relativePath);
  return resolved != null && await File(resolved.absolutePath).exists();
}

Future<bool> _pathExists(
  PhaseValidationInput input,
  String relativePath,
) async {
  final resolved = await _resolveMaybe(input, relativePath);
  if (resolved == null) return false;
  final type = await FileSystemEntity.type(resolved.absolutePath);
  return type != FileSystemEntityType.notFound;
}

Future<WorkspacePath?> _resolveMaybe(
  PhaseValidationInput input,
  String relativePath,
) async {
  try {
    return await input.sandbox.resolve(input.workspaceRoot, relativePath);
  } catch (_) {
    return null;
  }
}

bool _jsonParses(String content) {
  try {
    jsonDecode(content);
    return true;
  } catch (_) {
    return false;
  }
}

bool _yamlParsesStructured(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return false;
  try {
    final node = loadYamlNode(trimmed);
    final value = node.value;
    return value is YamlMap || value is YamlList;
  } on YamlException {
    return false;
  } catch (_) {
    return false;
  }
}

String _classedCommands(
  Iterable<String> commands,
  TerminalCommandClassifierFn classifyCommand,
) {
  return commands
      .map((command) => '${classifyCommand(command).wire}: $command')
      .join('; ');
}

bool _pathMatchesConstraint(String filePath, String constraint) {
  final candidate = _normaliseRelativePath(filePath);
  final rule = _normaliseRelativePath(constraint);
  if (rule.contains('*')) {
    final expression =
        '^${RegExp.escape(rule).replaceAll(r'\*', '.*')}${rule.endsWith('/') ? '.*' : r'$'}';
    return RegExp(expression).hasMatch(candidate);
  }
  return candidate == rule || candidate.startsWith('$rule/');
}

String _normaliseRelativePath(String value) {
  final normalised = path.posix.normalize(value.replaceAll('\\', '/'));
  if (normalised == '.') return normalised;
  return normalised.startsWith('./') ? normalised.substring(2) : normalised;
}
