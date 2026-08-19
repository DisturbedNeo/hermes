import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/subagent_service.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/tools/tool.dart';
import 'package:hermes/core/tools/tool_error.dart';

abstract class WorkspaceTool extends Tool {
  final WorkspaceSandbox sandbox;

  WorkspaceTool(this.sandbox);

  @override
  bool get requiresWorkspace => true;

  Future<Map<String, dynamic>> run(
    Map<String, dynamic> input,
    WorkspaceToolContext context,
  );

  @override
  Future<String> process(String input, {WorkspaceToolContext? context}) async {
    if (context == null || context.workspace.missing) {
      return jsonEncode(
        toolErrorPayload(
          code: 'workspace_unavailable',
          message: 'No active workspace is available.',
          disposition: TaskToolErrorDisposition.retryable,
        ),
      );
    }

    try {
      final decoded = jsonDecode(input);
      final args = decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
      final result = await run(args, context);
      return jsonEncode(result);
    } on OperationCancelledException {
      rethrow;
    } on WorkspaceSandboxException catch (e) {
      return jsonEncode(
        toolErrorPayload(
          code: e.code,
          message: e.message,
          disposition: TaskToolErrorDisposition.advisory,
        ),
      );
    } on FormatException catch (e) {
      return jsonEncode(
        toolErrorPayload(
          code: 'invalid_tool_arguments',
          message: e.toString(),
          disposition: TaskToolErrorDisposition.advisory,
        ),
      );
    } on FileSystemException catch (e) {
      return jsonEncode(
        toolErrorPayload(
          code: 'workspace_io_failure',
          message: e.message,
          disposition: TaskToolErrorDisposition.retryable,
        ),
      );
    } catch (e) {
      return jsonEncode(
        toolErrorPayload(
          code: 'unexpected_tool_failure',
          message: e.toString(),
          disposition: TaskToolErrorDisposition.fatal,
        ),
      );
    }
  }

  String stringArg(
    Map<String, dynamic> input,
    String key, {
    String fallback = '',
  }) {
    final value = input[key];
    return value is String ? value : fallback;
  }

  bool boolArg(Map<String, dynamic> input, String key) => input[key] == true;
}

class ListDirectoryTool extends WorkspaceTool {
  ListDirectoryTool(super.sandbox);

  @override
  final String id = 'list_directory';
  @override
  final String name = 'List directory';
  @override
  final String description =
      'Lists files and folders inside the active workspace.';
  @override
  final Map<String, dynamic> schema = {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Workspace-relative directory path. Use "." for root.',
      },
    },
  };

  @override
  Future<Map<String, dynamic>> run(
    Map<String, dynamic> input,
    WorkspaceToolContext context,
  ) async {
    return {
      'entries': await sandbox.listDirectory(
        context.workspace.rootPath,
        stringArg(input, 'path', fallback: '.'),
        cancellationToken: context.cancellationToken,
      ),
    };
  }
}

class ReadFileTool extends WorkspaceTool {
  ReadFileTool(super.sandbox);

  @override
  final String id = 'read_file';
  @override
  final String name = 'Read file';
  @override
  final String description =
      'Reads an existing UTF-8 text file inside the workspace. Use list_directory for directories.';
  @override
  final Map<String, dynamic> schema = {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Workspace-relative file path.',
      },
      'request': {
        'type': 'string',
        'description':
            'Optional request to extract specific information from the file (e.g., "list all exported functions", "summarize the file structure", "find the main class definition"). When provided, returns only the extracted information instead of the full file content.',
      },
    },
    'required': ['path'],
  };

  @override
  Future<Map<String, dynamic>> run(
    Map<String, dynamic> input,
    WorkspaceToolContext context,
  ) async {
    final filePath = stringArg(input, 'path');
    final request = stringArg(input, 'request', fallback: '');

    if (request.isEmpty) {
      // Standard read - return full file content
      return sandbox.readFile(
        context.workspace.rootPath,
        filePath,
        cancellationToken: context.cancellationToken,
      );
    }

    // Request mode - extract specific information using subagent
    final subagentService = context.subagentService as SubagentService?;
    if (subagentService == null) {
      return {
        ...toolErrorPayload(
          code: 'tool_dependency_unavailable',
          message:
              'Subagent service not available. Cannot perform extraction request.',
          disposition: TaskToolErrorDisposition.retryable,
        ),
      };
    }

    try {
      final fileContent = await sandbox.readFile(
        context.workspace.rootPath,
        filePath,
        cancellationToken: context.cancellationToken,
      );

      // Check if the read returned an error
      if (fileContent.containsKey('error')) {
        return fileContent;
      }

      final content = fileContent['content'] as String? ?? '';

      if (content.isEmpty) {
        return {'extracted': ''};
      }

      final extracted = await subagentService.extract(
        fileContent: content,
        extractionRequest: request,
        filePath: filePath,
      );

      return {'extracted': extracted};
    } on OperationCancelledException {
      rethrow;
    } on WorkspaceSandboxException {
      // Preserve workspace validation errors so WorkspaceTool.process can
      // classify them as advisory, just like a standard read_file call.
      rethrow;
    } catch (e) {
      return toolErrorPayload(
        code: 'subagent_extraction_failed',
        message: 'Failed to extract information: $e',
        disposition: TaskToolErrorDisposition.retryable,
      );
    }
  }
}

class WriteFileTool extends WorkspaceTool {
  WriteFileTool(super.sandbox);

  @override
  final String id = 'write_file';
  @override
  final String name = 'Write file';
  @override
  final String description =
      'Creates or replaces a UTF-8 text file inside the workspace.';
  @override
  final Map<String, dynamic> schema = {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Workspace-relative file path.',
      },
      'content': {'type': 'string', 'description': 'Complete file content.'},
    },
    'required': ['path', 'content'],
  };

  @override
  Future<Map<String, dynamic>> run(
    Map<String, dynamic> input,
    WorkspaceToolContext context,
  ) {
    return sandbox.writeFile(
      context.workspace.rootPath,
      stringArg(input, 'path'),
      stringArg(input, 'content'),
      cancellationToken: context.cancellationToken,
    );
  }
}

class PatchFileTool extends WorkspaceTool {
  PatchFileTool(super.sandbox);

  @override
  final String id = 'patch_file';
  @override
  final String name = 'Patch file';
  @override
  final String description =
      'Replaces exact text in a workspace file. Read the file first.';
  @override
  final Map<String, dynamic> schema = {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Workspace-relative file path.',
      },
      'old_text': {'type': 'string', 'description': 'Exact text to replace.'},
      'new_text': {'type': 'string', 'description': 'Replacement text.'},
      'replace_all': {
        'type': 'boolean',
        'description': 'Replace every occurrence instead of the first one.',
      },
    },
    'required': ['path', 'old_text', 'new_text'],
  };

  @override
  Future<Map<String, dynamic>> run(
    Map<String, dynamic> input,
    WorkspaceToolContext context,
  ) {
    return sandbox.patchFile(
      context.workspace.rootPath,
      stringArg(input, 'path'),
      stringArg(input, 'old_text'),
      stringArg(input, 'new_text'),
      replaceAll: boolArg(input, 'replace_all'),
      cancellationToken: context.cancellationToken,
    );
  }
}

class SearchFilesTool extends WorkspaceTool {
  SearchFilesTool(super.sandbox);

  @override
  final String id = 'search_files';
  @override
  final String name = 'Search files';
  @override
  final String description =
      'Searches text files inside the workspace. Hidden dot-folders (e.g. .git, .pub-cache) are excluded by default. To search inside a dot-folder, provide its path explicitly via the path parameter.';
  @override
  final Map<String, dynamic> schema = {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': 'Text to search for.'},
      'path': {
        'type': 'string',
        'description':
            'Workspace-relative directory path. Defaults to root (which excludes dot-folders). Provide an explicit path like ".agent" to search inside a dot-folder.',
      },
    },
    'required': ['query'],
  };

  @override
  Future<Map<String, dynamic>> run(
    Map<String, dynamic> input,
    WorkspaceToolContext context,
  ) async {
    return {
      'matches': await sandbox.searchFiles(
        context.workspace.rootPath,
        stringArg(input, 'query'),
        relativePath: stringArg(input, 'path', fallback: '.'),
        cancellationToken: context.cancellationToken,
      ),
    };
  }
}

class CreateDirectoryTool extends WorkspaceTool {
  CreateDirectoryTool(super.sandbox);

  @override
  final String id = 'create_directory';
  @override
  final String name = 'Create directory';
  @override
  final String description = 'Creates a folder inside the workspace.';
  @override
  final Map<String, dynamic> schema = {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Workspace-relative directory path.',
      },
    },
    'required': ['path'],
  };

  @override
  Future<Map<String, dynamic>> run(
    Map<String, dynamic> input,
    WorkspaceToolContext context,
  ) {
    return sandbox.createDirectory(
      context.workspace.rootPath,
      stringArg(input, 'path'),
    );
  }
}

class RenamePathTool extends WorkspaceTool {
  RenamePathTool(super.sandbox);

  @override
  final String id = 'rename_path';
  @override
  final String name = 'Rename path';
  @override
  final String description =
      'Renames or moves a file or folder in the workspace.';
  @override
  final Map<String, dynamic> schema = {
    'type': 'object',
    'properties': {
      'from': {'type': 'string', 'description': 'Existing workspace path.'},
      'to': {'type': 'string', 'description': 'Destination workspace path.'},
    },
    'required': ['from', 'to'],
  };

  @override
  Future<Map<String, dynamic>> run(
    Map<String, dynamic> input,
    WorkspaceToolContext context,
  ) {
    return sandbox.renamePath(
      context.workspace.rootPath,
      stringArg(input, 'from'),
      stringArg(input, 'to'),
    );
  }
}

class DeletePathTool extends WorkspaceTool {
  DeletePathTool(super.sandbox);

  @override
  final String id = 'delete_path';
  @override
  final String name = 'Delete path';
  @override
  final String description = 'Deletes a file or folder inside the workspace.';
  @override
  final Map<String, dynamic> schema = {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'Workspace-relative path.'},
      'recursive': {
        'type': 'boolean',
        'description': 'Required to delete non-empty directories.',
      },
    },
    'required': ['path'],
  };

  @override
  Future<Map<String, dynamic>> run(
    Map<String, dynamic> input,
    WorkspaceToolContext context,
  ) {
    return sandbox.deletePath(
      context.workspace.rootPath,
      stringArg(input, 'path'),
      recursive: boolArg(input, 'recursive'),
    );
  }
}

class RunCommandTool extends WorkspaceTool {
  RunCommandTool(super.sandbox);

  @override
  final String id = 'run_command';
  @override
  final String name = 'Run command';
  @override
  final String description =
      'Runs a user-approved shell command on the host, with the workspace as its working directory. The command is not sandboxed and may access resources outside the workspace.';
  @override
  final Map<String, dynamic> schema = {
    'type': 'object',
    'properties': {
      'command': {
        'type': 'string',
        'description':
            'Single shell command line to run, for example "git status --short" or "dart test".',
      },
      'args': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'Optional argument list. When present, command is treated as an executable and each argument is shell-quoted.',
      },
      'working_directory': {
        'type': 'string',
        'description':
            'Workspace-relative working directory. Defaults to root.',
      },
    },
    'required': ['command'],
  };

  @override
  Future<Map<String, dynamic>> run(
    Map<String, dynamic> input,
    WorkspaceToolContext context,
  ) {
    if (!context.workspace.commandExecutionApproved) {
      return Future.value(
        toolErrorPayload(
          code: 'command_execution_disabled',
          message:
              'Host terminal access is disabled for this session. Enable it from the workspace chip first.',
          disposition: TaskToolErrorDisposition.advisory,
        ),
      );
    }

    final rawArgs = input['args'];
    final hasDeclaredArgs = input.containsKey('args');
    final args = rawArgs is List
        ? rawArgs.map((item) => item.toString()).toList()
        : <String>[];
    final command = stringArg(input, 'command');

    return sandbox.runCommand(
      context.workspace.rootPath,
      command: hasDeclaredArgs ? null : command,
      executable: hasDeclaredArgs ? command : null,
      arguments: args,
      workingDirectory: stringArg(input, 'working_directory', fallback: '.'),
      cancellationToken: context.cancellationToken,
    );
  }
}
