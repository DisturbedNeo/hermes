import 'package:hermes/core/json_parsing.dart';
import 'package:hermes/core/uuid.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/workspace/application/sandbox_policy.dart';
import 'package:hermes/features/model/application/model_completion.dart';
import 'package:hermes/features/persistence/application/task_json.dart';
import 'package:hermes/features/workspace/application/terminal_command_parser.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';
import 'package:path/path.dart' as path;

class TaskAllowedCommand {
  final String command;
  final String workingDirectory;

  const TaskAllowedCommand({
    required this.command,
    required this.workingDirectory,
  });
}

/// Applies task-scoped tool permissions and workspace artifact policy.
///
/// Model completion and task lifecycle are intentionally outside this class.
/// This is the authoritative boundary for read-only command whitelists,
/// declared artifact writes, and the final call into ToolRegistryPort.
abstract interface class TaskToolExecutionPort {
  Future<ToolResult> execute({
    required ModelToolCall call,
    required TaskAggregate task,
    required TaskStep step,
    required Set<String> allowedToolIds,
    required List<TaskAllowedCommand> allowedCommands,
    required WorkspaceToolContext context,
    required String? blockedReason,
  });

  List<TaskArtifact> artifactsFromToolCalls(
    String taskId,
    TaskStep step,
    List<TaskToolCallRecord> toolCalls,
  );
}

class TaskToolExecutionService implements TaskToolExecutionPort {
  const TaskToolExecutionService({
    required ToolProtocolAdapter protocol,
    required WorkspaceTaskToolPort sandbox,
  }) : _protocol = protocol,
       _sandbox = sandbox;

  final ToolProtocolAdapter _protocol;
  final WorkspaceTaskToolPort _sandbox;

  @override
  Future<ToolResult> execute({
    required ModelToolCall call,
    required TaskAggregate task,
    required TaskStep step,
    required Set<String> allowedToolIds,
    required List<TaskAllowedCommand> allowedCommands,
    required WorkspaceToolContext context,
    required String? blockedReason,
  }) async {
    if (blockedReason != null) {
      return _error(
        code: 'loop_guard',
        message: 'Tool call skipped by task runner.',
        disposition: TaskToolErrorDisposition.advisory,
        details: {'reason': blockedReason, 'skipped': true},
      );
    }

    if (!allowedToolIds.contains(call.name)) {
      return _error(
        code: 'tool_not_available',
        message: 'Tool is not available for this task step.',
        disposition: TaskToolErrorDisposition.advisory,
        details: {
          'tool': call.name,
          'mayEditFiles': step.mayEditFiles,
          'availableTools': allowedToolIds.toList()..sort(),
          'reason': step.mayEditFiles
              ? 'The tool was not exposed to the task runner.'
              : 'This read-only step can read files and create new task-owned artifact files, but cannot edit source files, overwrite files, run terminal commands, rename paths, or delete paths.',
        },
      );
    }

    if (!step.mayEditFiles && call.name == 'run_command') {
      final whitelistError = _readOnlyCommandWhitelistError(
        call,
        allowedCommands,
      );
      if (whitelistError != null) return whitelistError;
    }

    if (!step.mayEditFiles && call.name == 'write_file') {
      return _executeReadOnlyArtifactWrite(
        call: call,
        task: task,
        step: step,
        context: context,
      );
    }
    if (step.mayEditFiles && call.name == 'write_file') {
      final artifactWriteError = await _taskArtifactWriteError(
        call: call,
        task: task,
        step: step,
        context: context,
      );
      if (artifactWriteError != null) return artifactWriteError;
    }

    return _protocol.executeTyped(
      toolId: call.name,
      argumentsJson: call.arguments,
      context: context,
    );
  }

  ToolResult? _readOnlyCommandWhitelistError(
    ModelToolCall call,
    List<TaskAllowedCommand> allowedCommands,
  ) {
    final decoded = TaskJson.decodeJsonOrString(call.arguments);
    if (decoded is! Map) {
      return _error(
        code: 'invalid_tool_arguments',
        message: 'run_command arguments must be a JSON object.',
        disposition: TaskToolErrorDisposition.advisory,
      );
    }
    final args = jsonMap(decoded);
    final command = TerminalCommandParser.commandTextFromParts(
      jsonString(args['command']),
      jsonStringList(args['args']),
    );
    final workingDirectory = path.normalize(
      jsonString(
        args['working_directory'] ?? args['workingDirectory'],
        fallback: '.',
      ),
    );
    final allowed = allowedCommands.any(
      (item) =>
          item.command == command &&
          path.normalize(item.workingDirectory) == workingDirectory,
    );
    if (allowed) return null;
    return _error(
      code: 'command_not_whitelisted',
      message:
          'Terminal command and working directory must exactly match a command_passes gate for this read-only step. Use the command exactly as listed without adding or removing arguments, flags, pipes, redirects, shell wrappers, or combined commands.',
      disposition: TaskToolErrorDisposition.advisory,
      details: {
        'command': command,
        'working_directory': workingDirectory,
        'allowedCommands': [
          for (final item in allowedCommands)
            {
              'command': item.command,
              'working_directory': item.workingDirectory,
            },
        ],
      },
    );
  }

  Future<ToolResult> _executeReadOnlyArtifactWrite({
    required ModelToolCall call,
    required TaskAggregate task,
    required TaskStep step,
    required WorkspaceToolContext context,
  }) async {
    try {
      final decoded = TaskJson.decodeJsonOrString(call.arguments);
      if (decoded is! Map) {
        return _error(
          code: 'invalid_tool_arguments',
          message: 'write_file arguments must be a JSON object.',
          disposition: TaskToolErrorDisposition.advisory,
        );
      }
      final rawPath = decoded['path'];
      final content = decoded['content'];
      if (rawPath is! String || rawPath.trim().isEmpty) {
        return _error(
          code: 'invalid_tool_arguments',
          message: 'write_file requires a path.',
          disposition: TaskToolErrorDisposition.advisory,
        );
      }
      if (content is! String) {
        return _error(
          code: 'invalid_tool_arguments',
          message: 'write_file requires string content.',
          disposition: TaskToolErrorDisposition.advisory,
        );
      }

      final resolved = await _sandbox.resolve(
        context.workspace.rootPath,
        rawPath,
        mustExist: false,
      );
      if (!_isInsideTaskDirectory(resolved.relativePath, task.id)) {
        return _error(
          code: 'artifact_path_denied',
          message: 'Read-only steps may only create task-owned artifact files.',
          disposition: TaskToolErrorDisposition.advisory,
          details: {
            'path': resolved.relativePath,
            'allowedPrefix': path.join('.agent', 'tasks', task.id),
          },
        );
      }
      final allowedPaths = _declaredCurrentStepArtifactPaths(task.id, step);
      if (!allowedPaths.contains(path.normalize(resolved.relativePath))) {
        return _error(
          code: 'artifact_not_declared',
          message:
              'Read-only steps may only create artifacts declared on the current step.',
          disposition: TaskToolErrorDisposition.advisory,
          details: {
            'path': resolved.relativePath,
            'allowedArtifactPaths': allowedPaths.toList()..sort(),
          },
        );
      }

      final inspected = await _sandbox.inspectPath(
        context.workspace.rootPath,
        resolved.relativePath,
      );
      if (inspected.exists) {
        return _error(
          code: 'read_only_overwrite_denied',
          message: 'Read-only steps cannot overwrite existing files.',
          disposition: TaskToolErrorDisposition.advisory,
          details: {'path': resolved.relativePath},
        );
      }

      final result = await _sandbox.writeFile(
        context.workspace.rootPath,
        resolved.relativePath,
        content,
      );
      return ToolSuccess(
        ToolPayload({'path': result.path, 'bytes': result.bytes}),
      );
    } on WorkspaceSandboxException catch (error) {
      return _error(
        code: error.code,
        message: error.message,
        disposition: TaskToolErrorDisposition.advisory,
      );
    } catch (error) {
      return _error(
        code: 'workspace_io_failure',
        message: error.toString(),
        disposition: TaskToolErrorDisposition.retryable,
      );
    }
  }

  Future<ToolResult?> _taskArtifactWriteError({
    required ModelToolCall call,
    required TaskAggregate task,
    required TaskStep step,
    required WorkspaceToolContext context,
  }) async {
    try {
      final decoded = TaskJson.decodeJsonOrString(call.arguments);
      if (decoded is! Map) return null;
      final rawPath = decoded['path'];
      if (rawPath is! String || rawPath.trim().isEmpty) return null;

      final resolved = await _sandbox.resolve(
        context.workspace.rootPath,
        rawPath,
        mustExist: false,
      );
      final artifactPath = path.normalize(resolved.relativePath);
      if (!_isInsideTaskDirectory(artifactPath, task.id)) return null;

      final allowedPaths = _declaredCurrentStepArtifactPaths(task.id, step);
      if (allowedPaths.contains(artifactPath)) return null;

      return _error(
        code: 'artifact_not_declared',
        message:
            'Task steps may only create artifacts declared on the current step.',
        disposition: TaskToolErrorDisposition.advisory,
        details: {
          'path': resolved.relativePath,
          'allowedArtifactPaths': allowedPaths.toList()..sort(),
        },
      );
    } on WorkspaceSandboxException catch (error) {
      return _error(
        code: error.code,
        message: error.message,
        disposition: TaskToolErrorDisposition.advisory,
      );
    } catch (error) {
      return _error(
        code: 'workspace_io_failure',
        message: error.toString(),
        disposition: TaskToolErrorDisposition.retryable,
      );
    }
  }

  bool _isInsideTaskDirectory(String relativePath, String taskId) {
    final segments = path.split(path.normalize(relativePath));
    return segments.length > 3 &&
        segments[0] == '.agent' &&
        segments[1] == 'tasks' &&
        segments[2] == taskId;
  }

  Set<String> _declaredCurrentStepArtifactPaths(String taskId, TaskStep step) {
    return {
          for (final artifact in step.artifacts)
            if (artifact.path.trim().isNotEmpty)
              path.normalize(artifact.path.trim()),
        }
        .where((artifactPath) => _isInsideTaskDirectory(artifactPath, taskId))
        .toSet();
  }

  /// Builds artifact provenance only from successful workspace mutations.
  @override
  List<TaskArtifact> artifactsFromToolCalls(
    String taskId,
    TaskStep step,
    List<TaskToolCallRecord> toolCalls,
  ) {
    final declarations = <String, TaskArtifact>{
      for (final artifact in step.artifacts)
        if (artifact.path.trim().isNotEmpty)
          path.normalize(artifact.path.trim()): artifact,
    };
    if (declarations.isEmpty) return const [];

    final seen = <String>{};
    final artifacts = <TaskArtifact>[];
    for (final call in toolCalls) {
      if (call.outcome != TaskToolCallOutcome.succeeded ||
          call.toolError != null) {
        continue;
      }
      final result = jsonMap(call.result);
      final pathValue = switch (call.toolName) {
        'write_file' ||
        'patch_file' ||
        'create_directory' => jsonString(result['path']),
        'rename_path' => jsonString(result['to']),
        _ => '',
      };
      final artifactPath = path.normalize(pathValue.trim());
      final declaration = declarations[artifactPath];
      if (declaration == null || !seen.add(artifactPath)) continue;
      final kind = call.toolName == 'create_directory' ? 'directory' : 'file';
      artifacts.add(
        TaskArtifact(
          path: artifactPath,
          id: 'artifact_${uuid.v7()}',
          description:
              declaration.description ?? 'Created by ${call.toolName}.',
          stepId: step.id,
          taskId: taskId,
          runId: call.runId,
          kind: kind,
          createdAt: call.timestamp,
        ),
      );
    }
    return artifacts;
  }

  ToolResult _error({
    required String code,
    required String message,
    required TaskToolErrorDisposition disposition,
    Map<String, dynamic> details = const {},
  }) => ToolFailure(
    code: code,
    message: message,
    details: ToolPayload({...details, 'error_disposition': disposition.wire}),
  );
}
