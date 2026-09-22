import 'dart:convert';

import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/planner_message_compactor.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/serialization/model_json.dart';

/// The common model-facing contract for project and task planning registries.
///
/// Registries own their domain command vocabulary and in-memory draft state.
/// They never persist a draft or expose workspace mutation tools.
abstract interface class PlanningToolRegistry {
  List<ToolDefinition> get toolDefinitions;

  /// The command which ends a planning session when it returns `ok: true`.
  String get terminalToolId;

  bool get allowsWorkspaceMutation;

  Future<String> execute(
    String toolId,
    String argumentsJson, {
    String? commandId,
  });

  Future<Map<String, dynamic>> invoke(
    String toolId,
    Map<String, dynamic> arguments, {
    String? commandId,
  });
}

/// Common argument failure used by domain registries while dispatching tools.
class PlanningToolArgumentException implements Exception {
  final String code;
  final String path;
  final String message;

  const PlanningToolArgumentException(this.code, this.path, this.message);

  @override
  String toString() => '$code ($path): $message';
}

class _PlanningAppliedCommand {
  final String fingerprint;
  final Map<String, dynamic> result;

  const _PlanningAppliedCommand(this.fingerprint, this.result);
}

/// Reusable JSON, idempotency, closure, and error-envelope plumbing for a
/// domain planning registry.
abstract class PlanningToolRegistryBase implements PlanningToolRegistry {
  final Map<String, _PlanningAppliedCommand> _commands = {};
  bool _terminalCommitted = false;

  /// Allows a domain registry to preserve its existing closed-session code.
  String get closedCode => 'planning_closed';

  String get closedMessage => 'The planning draft was already committed.';

  @override
  Future<String> execute(
    String toolId,
    String argumentsJson, {
    String? commandId,
  }) async {
    try {
      final decoded = jsonDecode(argumentsJson);
      if (decoded is! Map) {
        return jsonEncode(
          error(
            code: 'invalid_argument',
            path: 'arguments',
            message: 'Tool arguments must be a JSON object.',
          ),
        );
      }
      final arguments = <String, dynamic>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String) {
          return jsonEncode(
            error(
              code: 'invalid_argument',
              path: 'arguments',
              message: 'Tool argument names must be strings.',
            ),
          );
        }
        arguments[entry.key as String] = entry.value;
      }
      return jsonEncode(await invoke(toolId, arguments, commandId: commandId));
    } on FormatException catch (error) {
      return jsonEncode(
        this.error(
          code: 'invalid_argument',
          path: 'arguments',
          message: 'Malformed JSON arguments: ${error.message}',
        ),
      );
    }
  }

  @override
  Future<Map<String, dynamic>> invoke(
    String toolId,
    Map<String, dynamic> arguments, {
    String? commandId,
  }) async {
    if (_terminalCommitted) {
      return error(code: closedCode, path: 'tool', message: closedMessage);
    }

    try {
      final key = commandId?.trim();
      final fingerprint = key == null || key.isEmpty
          ? null
          : jsonEncode({'tool': toolId, 'arguments': arguments});
      if (key != null && key.isNotEmpty) {
        final previous = _commands[key];
        if (previous != null) {
          if (previous.fingerprint != fingerprint) {
            throw argument(
              'duplicate_command',
              'command',
              'Command $key was already used with different arguments.',
            );
          }
          return previous.result;
        }
      }

      final result = await dispatch(toolId, arguments, commandId: commandId);
      final response = {'ok': true, ...result};
      if (key != null && key.isNotEmpty) {
        _commands[key] = _PlanningAppliedCommand(fingerprint!, response);
      }
      if (toolId == terminalToolId && response['ok'] == true) {
        _terminalCommitted = true;
      }
      return response;
    } on PlanningToolArgumentException catch (error) {
      return this.error(
        code: error.code,
        path: error.path,
        message: error.message,
      );
    } catch (error) {
      return domainError(error);
    }
  }

  /// Dispatches a validated JSON object to domain-specific planning logic.
  Future<Map<String, dynamic>> dispatch(
    String toolId,
    Map<String, dynamic> arguments, {
    String? commandId,
  });

  PlanningToolArgumentException argument(
    String code,
    String path,
    String message,
  ) => PlanningToolArgumentException(code, path, message);

  /// Rejects fields that belong to Hermes-owned runtime or persistence state.
  /// Domains can add fields specific to their document shape while sharing
  /// the common ownership boundary.
  void rejectPersistentFields(
    Map<String, dynamic> value,
    String fieldPath, {
    Set<String> additional = const {},
    String message = 'Planning commands generate persistent fields; the field is not accepted.',
  }) {
    const common = {
      'id',
      'status',
      'created_at',
      'createdAt',
      'updated_at',
      'updatedAt',
      'runs',
      'failure',
      'gates',
      'expected_evidence',
      'expectedEvidence',
      'completed_at',
      'completedAt',
    };
    for (final field in {...common, ...additional}) {
      if (value.containsKey(field)) {
        throw argument('invalid_argument', '$fieldPath.$field', message);
      }
    }
  }

  Map<String, dynamic> error({
    required String code,
    required String path,
    required String message,
    Map<String, dynamic> extra = const {},
  }) => {'ok': false, 'code': code, 'path': path, 'message': message, ...extra};

  /// Domain registries override this to map builder/view exceptions while
  /// retaining the shared fallback for unexpected failures.
  Map<String, dynamic> domainError(Object error) => this.error(
    code: 'planning_tool_failed',
    path: 'tool',
    message: 'The planning command could not be applied: $error',
  );
}

class PlanningRunRequest {
  final ChatClient client;
  final PlanningToolRegistry registry;
  final String label;
  final String system;
  final String user;
  final int maxToolCalls;
  final TaskModelOutputSink? onModelOutput;
  final CancellationToken? cancellationToken;

  const PlanningRunRequest({
    required this.client,
    required this.registry,
    required this.label,
    required this.system,
    required this.user,
    this.maxToolCalls = PlanningToolCallRunner.defaultMaxToolCalls,
    this.onModelOutput,
    this.cancellationToken,
  });
}

class PlanningRunResult {
  final Map<String, dynamic> payload;
  final PlanningMetrics planningMetrics;
  final int modelCalls;
  final bool committed;

  const PlanningRunResult({
    required this.payload,
    this.planningMetrics = const PlanningMetrics(),
    this.modelCalls = 0,
    this.committed = false,
  });

  bool get ok => payload['ok'] == true;

  String? get code => payload['code']?.toString();

  String? get message => payload['message']?.toString();

  Map<String, dynamic> toMap() => {
    ...payload,
    'model_calls': modelCalls,
    'planning_metrics': ModelJson.encode(planningMetrics),
  };
}

/// Runs the shared model/tool loop used by both planning domains.
class PlanningToolCallRunner {
  const PlanningToolCallRunner();

  static const int defaultMaxToolCalls = 128;

  Future<PlanningRunResult> complete(PlanningRunRequest request) async {
    var messages = <ChatMessage>[
      ChatMessage(role: 'system', content: request.system),
      ChatMessage(role: 'user', content: request.user),
    ];
    final extraParams = ToolCaller.buildExtraParams(
      addGenerationPrompt: true,
      toolDefs: request.registry.toolDefinitions,
    );
    var toolCallCount = 0;
    var turn = 0;
    var metrics = const PlanningMetrics();

    while (true) {
      request.cancellationToken?.throwIfCancelled();
      turn++;
      final completion = await _complete(
        request: request,
        messages: messages,
        extraParams: extraParams,
      );
      request.cancellationToken?.throwIfCancelled();
      metrics = _recordModelCall(
        metrics,
        messages: messages,
        extraParams: extraParams,
        completion: completion,
      );

      if (completion.toolCalls.isEmpty) {
        final text = completion.content.trim().isNotEmpty
            ? completion.content.trim()
            : completion.reasoning.trim();
        return _result(
          payload: {
            'ok': false,
            'code': 'planning_protocol_violation',
            'message': text.isEmpty
                ? 'The planner returned no planning command.'
                : 'The planner returned text instead of a planning command.',
          },
          metrics: metrics,
          modelCalls: turn,
        );
      }

      final assistantCalls = <Map<String, dynamic>>[];
      for (var index = 0; index < completion.toolCalls.length; index++) {
        final call = completion.toolCalls[index];
        final commandId = _commandId(call, turn, index, request.label);
        assistantCalls.add({
          'id': commandId,
          'type': 'function',
          'function': {
            'name': call.name,
            'arguments': _decodeJsonOrString(call.arguments),
          },
        });
      }
      messages.add(
        ChatMessage(
          role: 'assistant',
          content: completion.content,
          reasoningContent: completion.reasoning,
          toolCalls: assistantCalls,
        ),
      );

      for (var index = 0; index < completion.toolCalls.length; index++) {
        request.cancellationToken?.throwIfCancelled();
        final call = completion.toolCalls[index];
        if (toolCallCount >= request.maxToolCalls) {
          return _result(
            payload: {
              'ok': false,
              'code': 'planning_safety_limit',
              'path': 'tool',
              'message':
                  'The planner reached the safety ceiling of ${request.maxToolCalls} tool calls before committing.',
            },
            metrics: metrics,
            modelCalls: turn,
          );
        }
        toolCallCount++;
        final commandId = _commandId(call, turn, index, request.label);
        final resultJson = await request.registry.execute(
          call.name,
          call.arguments,
          commandId: commandId,
        );
        _emit(
          request.onModelOutput,
          TaskModelOutputEvent(
            type: TaskModelOutputEventType.toolResult,
            label: request.label,
            text: resultJson,
            toolIndex: index,
          ),
        );
        messages.add(
          ChatMessage(role: 'tool', content: resultJson, toolCallId: commandId),
        );

        final result = _decodeMap(resultJson);
        metrics = _recordToolResult(metrics, resultJson, result);
        if (call.name == request.registry.terminalToolId &&
            result?['ok'] == true) {
          for (
            var remaining = index + 1;
            remaining < completion.toolCalls.length;
            remaining++
          ) {
            _emit(
              request.onModelOutput,
              TaskModelOutputEvent(
                type: TaskModelOutputEventType.toolResult,
                label: request.label,
                text: jsonEncode({
                  'skipped': true,
                  'reason': 'The planning commit ended the draft.',
                }),
                toolIndex: remaining,
              ),
            );
          }
          return _result(
            payload: result ??
                {
                  'ok': false,
                  'code': 'planning_tool_failed',
                  'path': request.registry.terminalToolId,
                  'message': 'The planning commit returned an invalid result.',
                },
            metrics: metrics,
            modelCalls: turn,
            committed: true,
          );
        }
      }
      messages = PlannerMessageCompactor.compact(messages);
    }
  }

  Future<ChatCompletionResponse> _complete({
    required PlanningRunRequest request,
    required List<ChatMessage> messages,
    required Map<String, dynamic> extraParams,
  }) async {
    _emit(
      request.onModelOutput,
      TaskModelOutputEvent(
        type: TaskModelOutputEventType.start,
        label: request.label,
      ),
    );
    final completion = request.client.supportsStreamingCancellation
        ? await _completeFromStream(
            request: request,
            messages: messages,
            extraParams: extraParams,
          )
        : await request.client.completeChatStreamed(
            messages: messages,
            extraParams: extraParams,
            onToken: (token) => _emitToken(request.onModelOutput, request.label, token),
            cancellationToken: request.cancellationToken,
            diagnosticsLabel: request.label,
          );
    _emit(
      request.onModelOutput,
      TaskModelOutputEvent(
        type: TaskModelOutputEventType.done,
        label: request.label,
      ),
    );
    return completion;
  }

  Future<ChatCompletionResponse> _completeFromStream({
    required PlanningRunRequest request,
    required List<ChatMessage> messages,
    required Map<String, dynamic> extraParams,
  }) async {
    final content = StringBuffer();
    final reasoning = StringBuffer();
    final toolCalls = <int, _StreamingPlanningToolCall>{};
    await for (final token in request.client.streamMessage(
      messages: messages,
      extraParams: extraParams,
      cancellationToken: request.cancellationToken,
      diagnosticsLabel: request.label,
    )) {
      _emitToken(request.onModelOutput, request.label, token);
      if (token.content != null) content.write(token.content);
      if (token.reasoning != null) reasoning.write(token.reasoning);
      final tool = token.tool;
      if (tool == null) continue;
      final call = toolCalls.putIfAbsent(
        tool.index,
        () => _StreamingPlanningToolCall(),
      );
      if (tool.id != null) call.id = tool.id;
      if (tool.name != null) call.name = tool.name;
      if (tool.argumentsChunk != null) call.arguments.write(tool.argumentsChunk);
    }
    return ChatCompletionResponse(
      content: content.toString(),
      reasoning: reasoning.toString(),
      toolCalls:
          (toolCalls.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
              .where((entry) => entry.value.name?.trim().isNotEmpty == true)
              .map(
                (entry) => ChatCompletionToolCall(
                  id: entry.value.id,
                  name: entry.value.name!,
                  arguments: entry.value.arguments.isEmpty
                      ? '{}'
                      : entry.value.arguments.toString(),
                ),
              )
              .toList(),
    );
  }

  void _emitToken(TaskModelOutputSink? sink, String label, ChatToken token) {
    final content = token.content;
    if (content != null && content.isNotEmpty) {
      _emit(
        sink,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.content,
          label: label,
          text: content,
          token: token,
        ),
      );
    }
    final reasoning = token.reasoning;
    if (reasoning != null && reasoning.isNotEmpty) {
      _emit(
        sink,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.reasoning,
          label: label,
          text: reasoning,
          token: token,
        ),
      );
    }
    final tool = token.tool;
    if (tool != null) {
      _emit(
        sink,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.toolCall,
          label: label,
          token: token,
          toolIndex: tool.index,
        ),
      );
    }
  }

  PlanningRunResult _result({
    required Map<String, dynamic> payload,
    required PlanningMetrics metrics,
    required int modelCalls,
    bool committed = false,
  }) => PlanningRunResult(
    payload: payload,
    planningMetrics: metrics,
    modelCalls: modelCalls,
    committed: committed,
  );

  static Object _decodeJsonOrString(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  static String _commandId(
    ChatCompletionToolCall call,
    int turn,
    int index,
    String label,
  ) {
    final id = call.id?.trim();
    return id == null || id.isEmpty ? '$label:$turn:$index' : id;
  }

  static Map<String, dynamic>? _decodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // A malformed result cannot be a successful commit.
    }
    return null;
  }

  static PlanningMetrics _recordModelCall(
    PlanningMetrics metrics, {
    required List<ChatMessage> messages,
    required Map<String, dynamic> extraParams,
    required ChatCompletionResponse completion,
  }) {
    final promptTokens =
        completion.diagnostics?.promptTokens ??
        ContextEstimator.estimateChatCompletionRequest(
          messages: messages,
          extraParams: extraParams,
        );
    return metrics.copyWith(
      planningCalls: metrics.planningCalls + 1,
      promptTokenEstimate: metrics.promptTokenEstimate + promptTokens,
    );
  }

  static PlanningMetrics _recordToolResult(
    PlanningMetrics metrics,
    String resultJson,
    Map<String, dynamic>? result,
  ) {
    final code = result?['code']?.toString().toLowerCase() ?? '';
    return metrics.copyWith(
      planningCommandCount: metrics.planningCommandCount + 1,
      toolResultTokenEstimate:
          metrics.toolResultTokenEstimate + ContextEstimator.estimateText(resultJson),
      invalidCommandCount:
          metrics.invalidCommandCount + (result?['ok'] == false ? 1 : 0),
      validationBlockerCount:
          metrics.validationBlockerCount + (_isValidationFailure(code) ? 1 : 0),
    );
  }

  static bool _isValidationFailure(String code) =>
      code.contains('validation') ||
      code.contains('duplicate') ||
      code.contains('unknown_ref') ||
      code.contains('stale_revision');

  static void _emit(TaskModelOutputSink? sink, TaskModelOutputEvent event) {
    sink?.call(event);
  }
}

class _StreamingPlanningToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}
