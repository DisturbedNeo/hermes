import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/planning_runtime.dart';
import 'package:hermes/core/services/planning_structured_output.dart';

void main() {
  test('shared registry owns idempotency and terminal closure', () async {
    final registry = _Registry();

    final first = await registry.invoke(
      'add',
      {'value': 'one'},
      commandId: 'command-1',
    );
    final repeated = await registry.invoke(
      'add',
      {'value': 'one'},
      commandId: 'command-1',
    );
    final conflicting = await registry.invoke(
      'add',
      {'value': 'two'},
      commandId: 'command-1',
    );

    expect(repeated, same(first));
    expect(conflicting['code'], 'duplicate_command');

    final committed = await registry.invoke('commit', const {});
    expect(committed['ok'], isTrue);
    final afterCommit = await registry.invoke('add', {'value': 'late'});
    expect(afterCommit['code'], 'planning_closed');
  });

  test('shared runner retries an invalid terminal command without closing', () async {
    final registry = _Registry(failFirstCommit: true);
    final client = _QueueClient([
      ChatCompletionResponse(
        content: '',
        toolCalls: [_tool('commit', '{}', id: 'commit-1')],
      ),
      ChatCompletionResponse(
        content: '',
        toolCalls: [_tool('commit', '{}', id: 'commit-2')],
      ),
    ]);

    final result = await const PlanningToolCallRunner().complete(
      PlanningRunRequest(
        client: client,
        registry: registry,
        label: 'Test planner',
        system: 'system',
        user: 'plan',
      ),
    );

    expect(result.ok, isTrue);
    expect(result.committed, isTrue);
    expect(result.modelCalls, 2);
    expect(registry.commitAttempts, 2);
  });

  test('shared runner enforces the configured safety ceiling', () async {
    final registry = _Registry();
    final client = _QueueClient([
      ChatCompletionResponse(
        content: '',
        toolCalls: [_tool('add', '{"value":"one"}', id: 'add-1')],
      ),
      ChatCompletionResponse(
        content: '',
        toolCalls: [_tool('add', '{"value":"two"}', id: 'add-2')],
      ),
    ]);

    final result = await const PlanningToolCallRunner().complete(
      PlanningRunRequest(
        client: client,
        registry: registry,
        label: 'Safety planner',
        system: 'system',
        user: 'plan',
        maxToolCalls: 1,
      ),
    );

    expect(result.ok, isFalse);
    expect(result.payload['code'], 'planning_safety_limit');
  });

  test('structured output performs one bounded repair attempt', () async {
    final client = _QueueClient([
      ChatCompletionResponse(content: 'not json'),
      ChatCompletionResponse(content: '{"complete":true}'),
    ]);

    final result = await const StructuredPlanningOutputService().completeObject(
      client: client,
      label: 'Structured test',
      system: 'system',
      user: 'evaluate',
      expectedShape: '{"complete":false}',
    );

    expect(result.value['complete'], isTrue);
    expect(result.repaired, isTrue);
    expect(result.planningMetrics.planningCalls, 2);
  });

  test('planning services honor cancellation before model execution', () async {
    final token = CancellationToken();
    await token.cancel();
    final client = _QueueClient([ChatCompletionResponse(content: '{}')]);

    expect(
      () => const PlanningToolCallRunner().complete(
        PlanningRunRequest(
          client: client,
          registry: _Registry(),
          label: 'Cancelled planner',
          system: 'system',
          user: 'plan',
          cancellationToken: token,
        ),
      ),
      throwsA(isA<OperationCancelledException>()),
    );
    expect(client.calls, 0);
  });
}

ChatCompletionToolCall _tool(String name, String arguments, {required String id}) =>
    ChatCompletionToolCall(id: id, name: name, arguments: arguments);

class _Registry extends PlanningToolRegistryBase {
  _Registry({this.failFirstCommit = false});

  final bool failFirstCommit;
  var commitAttempts = 0;

  @override
  List<ToolDefinition> get toolDefinitions => const [
    ToolDefinition(
      id: 'add',
      name: 'Add',
      description: 'Add a value.',
      schema: {'type': 'object'},
    ),
    ToolDefinition(
      id: 'commit',
      name: 'Commit',
      description: 'Commit the draft.',
      schema: {'type': 'object'},
    ),
  ];

  @override
  String get terminalToolId => 'commit';

  @override
  bool get allowsWorkspaceMutation => false;

  @override
  Future<Map<String, dynamic>> dispatch(
    String toolId,
    Map<String, dynamic> arguments, {
    String? commandId,
  }) async {
    if (toolId == 'add') return {'value': arguments['value']};
    if (toolId == 'commit') {
      commitAttempts++;
      if (failFirstCommit && commitAttempts == 1) {
        return error(
          code: 'invalid_plan',
          path: 'plan',
          message: 'The draft is incomplete.',
        );
      }
      return {'committed': true};
    }
    throw argument('unknown_tool', 'tool', 'Unknown tool $toolId.');
  }
}

class _QueueClient extends ChatClient {
  _QueueClient(this.responses)
    : super(baseUrl: 'http://localhost', model: 'test');

  final List<ChatCompletionResponse> responses;
  var _index = 0;
  var calls = 0;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    Object? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async {
    calls++;
    final index = _index < responses.length ? _index : responses.length - 1;
    _index++;
    return responses[index];
  }

  @override
  void dispose() {}
}
