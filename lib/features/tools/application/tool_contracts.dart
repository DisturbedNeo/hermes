import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Typed description of a tool's argument contract.
///
/// Only protocol adapters may turn this into the JSON-schema wire document.
class ToolSchema {
  const ToolSchema(this._fields);

  final Map<String, Object?> _fields;

  Object? operator [](String key) => _fields[key];

  Map<String, Object?> toWire() => _wireMap(_fields);

  static Map<String, Object?> _wireMap(Map<String, Object?> values) => {
    for (final entry in values.entries) entry.key: _wireValue(entry.value),
  };

  static Object? _wireValue(Object? value) {
    if (value is ToolSchema) return value.toWire();
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _wireValue(entry.value),
      };
    }
    if (value is Iterable) return value.map(_wireValue).toList();
    return value;
  }
}

class ToolDefinition {
  const ToolDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.schema,
  });

  final String id;
  final String name;
  final String description;
  final ToolSchema schema;
}

/// Validated tool arguments used by application code.
class ToolArguments {
  const ToolArguments([Map<String, Object?> values = const {}])
    : _values = values;

  factory ToolArguments.fromValues(Map<String, Object?> values) =>
      ToolArguments(values);

  final Map<String, Object?> _values;

  Object? operator [](String key) => _values[key];

  Map<String, Object?> toValues() => Map.unmodifiable(_values);
}

/// Typed request crossing an application/tool boundary. JSON is decoded once
/// at the protocol adapter and is not passed through the application graph.
class ToolRequest {
  const ToolRequest({
    required this.toolId,
    this.arguments = const ToolArguments(),
    this.context,
  });

  final String toolId;
  final ToolArguments arguments;
  final ToolContext? context;

  ToolRequest copyWith({
    String? toolId,
    ToolArguments? arguments,
    ToolContext? context,
  }) => ToolRequest(
    toolId: toolId ?? this.toolId,
    arguments: arguments ?? this.arguments,
    context: context ?? this.context,
  );
}

/// Framework-neutral workspace identity used by application ports.
class ToolWorkspace {
  const ToolWorkspace({
    required this.rootPath,
    this.displayName = '',
    this.missing = false,
    this.commandExecutionApproved = false,
  });

  final String rootPath;
  final String displayName;
  final bool missing;
  final bool commandExecutionApproved;
}

enum ToolPermission { none, readWorkspace, writeWorkspace, executeCommand }

class ToolContext {
  const ToolContext({
    this.workspace,
    this.permission = ToolPermission.none,
    this.cancellationToken,
    this.subagentService,
  });

  final ToolWorkspace? workspace;
  final ToolPermission permission;
  final CancellationToken? cancellationToken;
  final WorkspaceSubagentCapability? subagentService;

  bool allows(ToolPermission required) => permission.index >= required.index;
}

sealed class ToolResult {
  const ToolResult();

  bool get isSuccess => this is ToolSuccess;
}

/// Structured values returned by a typed tool. Wire encoding is owned by the
/// dedicated protocol adapter, not by this application value object.
class ToolPayload {
  const ToolPayload([Map<String, Object?> values = const {}])
    : _values = values;

  final Map<String, Object?> _values;

  Object? operator [](String key) => _values[key];

  Map<String, Object?> toValues() => Map.unmodifiable(_values);
}

class ToolSuccess extends ToolResult {
  const ToolSuccess(this.value);

  final ToolPayload value;
}

class ToolFailure extends ToolResult {
  const ToolFailure({
    required this.code,
    required this.message,
    this.details = const ToolPayload(),
  });

  final String code;
  final String message;
  final ToolPayload details;
}

/// Typed registry boundary used by feature application ports.
abstract interface class ToolRegistryPort {
  List<ToolDefinition> getToolDefinitions({
    List<String> ids,
    bool includeWorkspaceTools,
  });

  Future<ToolResult> executeTyped(ToolRequest request);

  ToolPermission permissionFor(String toolId);

  List<String> defaultToolIds({required bool includeWorkspaceTools});
}
