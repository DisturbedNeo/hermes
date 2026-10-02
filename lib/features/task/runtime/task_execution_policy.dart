import 'package:hermes/core/json_parsing.dart';
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

  List<TaskGate> completionGates(Task task, TaskStep step) {
    final hasRemainingSteps = task.steps.any((candidate) {
      if (candidate.id == step.id) return false;
      return candidate.status == TaskStepStatus.pending ||
          candidate.status == TaskStepStatus.approved ||
          candidate.status == TaskStepStatus.blocked ||
          candidate.status == TaskStepStatus.failed;
    });
    return [...step.gates, if (!hasRemainingSteps) ...task.gates];
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

  List<TaskAllowedCommand> allowedCommands(Task task, TaskStep step) {
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
