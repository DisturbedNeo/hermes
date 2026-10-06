import 'dart:convert';

import 'package:hermes/features/chat/application/protocol/context_estimator.dart';
import 'package:hermes/features/tools/application/protocol/tool_call_protocol_adapter.dart';
import 'package:hermes/core/contracts/model_conversation.dart';
import 'package:hermes/features/chat/application/protocol/chat_message_wire_adapter.dart';
import 'package:hermes/features/task/application/contracts/planning_metrics.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/features/model/application/model_completion.dart';

export 'package:hermes/features/model/application/model_request.dart';
import 'package:hermes/features/task/application/protocol/planner_message_compactor.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/core/model_json.dart';

export 'package:hermes/features/task/application/protocol/planning_protocol_adapter.dart';
import 'package:hermes/features/task/application/protocol/planning_protocol_adapter.dart';
import 'package:hermes/features/task/application/protocol/planning_contracts.dart';

export 'package:hermes/features/task/application/protocol/planning_contracts.dart';

class _PlanningAppliedCommand {
  final String fingerprint;
  final PlanningResponse result;

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
  Future<PlanningResponse> invoke(
    String toolId,
    PlanningArguments arguments, {
    String? commandId,
  }) async {
    if (_terminalCommitted) {
      return PlanningResponse.fromWire(
        error(code: closedCode, path: 'tool', message: closedMessage),
      );
    }

    try {
      final key = commandId?.trim();
      final fingerprint = key == null || key.isEmpty
          ? null
          : jsonEncode({'tool': toolId, 'arguments': arguments.toWire()});
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

      final response = await dispatch(toolId, arguments, commandId: commandId);
      if (key != null && key.isNotEmpty) {
        _commands[key] = _PlanningAppliedCommand(fingerprint!, response);
      }
      if (toolId == terminalToolId && response.ok) {
        _terminalCommitted = true;
      }
      return response;
    } on PlanningToolArgumentException catch (error) {
      return PlanningResponse.fromWire(
        this.error(
          code: error.code,
          path: error.path,
          message: error.message,
          extra: error.details.isEmpty ? const {} : {'details': error.details},
        ),
      );
    } catch (error) {
      return PlanningResponse.fromWire(domainError(error));
    }
  }

  /// Dispatches typed protocol arguments to domain-specific planning logic.
  /// JSON encoding remains owned by [PlanningProtocolAdapter].
  Future<PlanningResponse> dispatch(
    String toolId,
    PlanningArguments arguments, {
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
    Object value,
    String fieldPath, {
    Set<String> additional = const {},
    String message =
        'Planning commands generate persistent fields; the field is not accepted.',
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
    bool contains(String field) => value is PlanningArguments
        ? value.containsKey(field)
        : (value as Map<String, dynamic>).containsKey(field);
    for (final field in {...common, ...additional}) {
      if (contains(field)) {
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
  final ModelGenerationPort client;
  final PlanningToolRegistry registry;
  final String label;
  final String system;
  final String user;
  final int maxToolCalls;
  final ModelOutputSink? onModelOutput;
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
  final PlanningResponse response;
  final PlanningMetrics planningMetrics;
  final int modelCalls;
  final bool committed;

  const PlanningRunResult({
    required this.response,
    this.planningMetrics = const PlanningMetrics(),
    this.modelCalls = 0,
    this.committed = false,
  });

  bool get ok => response.ok;

  String? get code => response['code']?.toString();

  String? get message => response['message']?.toString();

  Map<String, dynamic> toMap() => {
    ...response.toWire(),
    'model_calls': modelCalls,
    'planning_metrics': ModelJson.encode(planningMetrics),
  };
}

/// Runs the shared model/tool loop used by both planning domains.
class PlanningToolCallRunner {
  const PlanningToolCallRunner();

  static const _chatMessageAdapter = ChatMessageWireAdapter();

  static const int defaultMaxToolCalls = 32;

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

      final assistantCalls = <ChatToolCall>[];
      for (var index = 0; index < completion.toolCalls.length; index++) {
        final call = completion.toolCalls[index];
        final commandId = _commandId(call, turn, index, request.label);
        assistantCalls.add(
          _chatMessageAdapter.toolCall(
            id: commandId,
            name: call.name,
            argumentsJson: call.arguments,
          ),
        );
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
        final resultJson = await PlanningProtocolAdapter(
          registry: request.registry,
        ).execute(call.name, call.arguments, commandId: commandId);
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
        final details = result?['details'];
        if (result?['ok'] == false &&
            details is Map &&
            details['repairable'] == false) {
          return _result(payload: result!, metrics: metrics, modelCalls: turn);
        }
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
            payload:
                result ??
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

  Future<ModelCompletion> _complete({
    required PlanningRunRequest request,
    required List<ChatMessage> messages,
    required ModelRequestOptions extraParams,
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
            onToken: (token) =>
                _emitToken(request.onModelOutput, request.label, token),
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

  Future<ModelCompletion> _completeFromStream({
    required PlanningRunRequest request,
    required List<ChatMessage> messages,
    required ModelRequestOptions extraParams,
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
      if (tool.argumentsChunk != null) {
        call.arguments.write(tool.argumentsChunk);
      }
    }
    return ModelCompletion(
      content: content.toString(),
      reasoning: reasoning.toString(),
      toolCalls:
          (toolCalls.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
              .where((entry) => entry.value.name?.trim().isNotEmpty == true)
              .map(
                (entry) => ModelToolCall(
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

  void _emitToken(ModelOutputSink? sink, String label, ChatToken token) {
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
    response: PlanningResponse.fromWire(payload),
    planningMetrics: metrics,
    modelCalls: modelCalls,
    committed: committed,
  );

  static String _commandId(
    ModelToolCall call,
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
    required ModelRequestOptions extraParams,
    required ModelCompletion completion,
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
          metrics.toolResultTokenEstimate +
          ContextEstimator.estimateText(resultJson),
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

  static void _emit(ModelOutputSink? sink, TaskModelOutputEvent event) {
    sink?.call(event);
  }
}

class _StreamingPlanningToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}
