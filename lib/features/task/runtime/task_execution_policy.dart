import 'package:hermes/core/json_parsing.dart';
import 'package:hermes/core/contracts/acceptance_compiler.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/runtime/task_tool_execution_service.dart';
import 'package:hermes/features/workspace/application/terminal_command_parser.dart';
import 'package:path/path.dart' as path;

/// Encapsulates task-step permission, gate, and control-tool policy.
///
/// Keeping this policy separate from the model/tool loop makes the execution
/// state machine responsible for transitions while this collaborator owns the
/// deterministic gate and tool-surface decisions.
class TaskExecutionPolicy {
  static const Set<String> readOnlyToolIds = {
    'calculator',
    'list_directory',
    'read_file',
    'search_files',
    'write_file',
  };

  static const Set<String> mutatingToolIds = {
    'write_file',
    'patch_file',
    'create_directory',
    'rename_path',
    'delete_path',
    'run_command',
  };

  const TaskExecutionPolicy();

  List<TaskGate> completionGates(TaskAggregate task, TaskStep step) {
    final hasRemainingSteps = task.steps.any((candidate) {
      if (candidate.id == step.id) return false;
      return candidate.status == TaskStepStatus.pending ||
          candidate.status == TaskStepStatus.approved ||
          candidate.status == TaskStepStatus.blocked ||
          candidate.status == TaskStepStatus.failed;
    });
    final compilation = const AcceptanceCompiler().compile(task.acceptance);
    final attached = {
      for (final ref in step.acceptanceRefs) ref,
    };
    final gates = [
      for (final item in compilation.verifiers)
        if (attached.contains(item.acceptanceRef))
          for (final kind in item.gateKinds) _acceptanceGate(item, 'step', kind),
      if (!hasRemainingSteps)
        for (final item in compilation.verifiers)
          if (!attached.contains(item.acceptanceRef))
            for (final kind in item.gateKinds)
              _acceptanceGate(item, 'task', kind),
      ..._internalSafetyGates(task, step),
    ];
    final seen = <String>{};
    return [
      for (final gate in gates)
        if (seen.add(
          _isEngineSafetyGate(gate)
              ? gate.id
              : '${gate.id}|${gate.scope}|${gate.params}',
        ))
          gate,
    ];
  }

  TaskGate _acceptanceGate(
    CompiledAcceptanceVerifier verifier,
    String scope,
    String kind,
  ) => TaskGate(
    id: kind,
    required: verifier.required,
    scope: scope,
    params: verifier.params,
    description: verifier.statement,
  );

  bool _isEngineSafetyGate(TaskGate gate) =>
      gate.id == 'no_tool_errors' || gate.id == 'no_failed_commands';

  /// Safety checks are engine-owned runtime policy, not planner-authored
  /// acceptance. They must still be present after a fresh-schema snapshot
  /// reload, where compiled gate definitions are intentionally not persisted.
  List<TaskGate> _internalSafetyGates(TaskAggregate task, TaskStep step) {
    if (!step.mayEditFiles && !_looksLikeCodingTask(task.objective)) {
      return const [];
    }
    return const [
      TaskGate(
        id: 'no_tool_errors',
        required: true,
        scope: 'task',
        description: 'No unresolved fatal workspace tool errors.',
      ),
      TaskGate(
        id: 'no_failed_commands',
        required: true,
        scope: 'task',
        description: 'No failed terminal commands after workspace mutation.',
      ),
    ];
  }

  bool _looksLikeCodingTask(String value) {
    final normalized = value.toLowerCase();
    return const [
      'code',
      'test',
      'build',
      'bug',
      'fix',
      'implement',
      'refactor',
      'compile',
      'flutter',
      'dart',
      'dotnet',
      'npm',
      'api',
    ].any(normalized.contains);
  }

  Set<String> allowedToolIds(
    TaskStep step,
    List<TaskAllowedCommand> allowedCommands,
  ) {
    if (!step.mayEditFiles) {
      return {
        ...readOnlyToolIds,
        if (allowedCommands.isNotEmpty) 'run_command',
      };
    }
    return {...readOnlyToolIds, ...mutatingToolIds};
  }

  List<TaskAllowedCommand> allowedCommands(TaskAggregate task, TaskStep step) {
    final seen = <String>{};
    final commands = <TaskAllowedCommand>[];
    for (final gate in completionGates(task, step)) {
      if (gate.id != 'command_passes') continue;
      final command = commandTextFromParts(
        jsonString(gate.params['command']),
        jsonStringList(gate.params['args']),
      );
      if (command.isEmpty) continue;
      final workingDirectory = path.normalize(
        jsonString(
          gate.params['working_directory'] ?? gate.params['workingDirectory'],
          fallback: '.',
        ),
      );
      final key = '$workingDirectory\x00$command';
      if (!seen.add(key)) continue;
      commands.add(
        TaskAllowedCommand(
          command: command,
          workingDirectory: workingDirectory,
        ),
      );
    }
    return commands;
  }

  String commandTextFromParts(String command, List<String> args) =>
      TerminalCommandParser.commandTextFromParts(command, args);

  bool isTerminalTool(String name) =>
      name == 'finish_task_step' ||
      name == 'task_request_user_decision' ||
      name == 'task_request_replan';
}
