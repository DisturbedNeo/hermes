import 'dart:convert';

import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/tools/tool.dart';

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
      return jsonEncode({'error': 'No active workspace is available.'});
    }

    try {
      final decoded = jsonDecode(input);
      final args = decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
      final result = await run(args, context);
      return jsonEncode(result);
    } catch (e) {
      return jsonEncode({'error': e.toString()});
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
  final String description = 'Reads a UTF-8 text file inside the workspace.';
  @override
  final Map<String, dynamic> schema = {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Workspace-relative file path.',
      },
    },
    'required': ['path'],
  };

  @override
  Future<Map<String, dynamic>> run(
    Map<String, dynamic> input,
    WorkspaceToolContext context,
  ) {
    return sandbox.readFile(
      context.workspace.rootPath,
      stringArg(input, 'path'),
    );
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
  final String description = 'Searches text files inside the workspace.';
  @override
  final Map<String, dynamic> schema = {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': 'Text to search for.'},
      'path': {
        'type': 'string',
        'description': 'Workspace-relative directory path. Defaults to root.',
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
      'Runs a guarded terminal command from inside the workspace. Requires user approval for the chat.';
  @override
  final Map<String, dynamic> schema = {
    'type': 'object',
    'properties': {
      'command': {
        'type': 'string',
        'description': 'Executable name, for example "git" or "dart".',
      },
      'args': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Command arguments.',
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
      return Future.value({
        'error':
            'Terminal commands are disabled for this chat. Enable them from the workspace chip first.',
      });
    }

    final rawArgs = input['args'];
    final args = rawArgs is List
        ? rawArgs.map((item) => item.toString()).toList()
        : <String>[];

    return sandbox.runCommand(
      context.workspace.rootPath,
      executable: stringArg(input, 'command'),
      arguments: args,
      workingDirectory: stringArg(input, 'working_directory', fallback: '.'),
    );
  }
}
