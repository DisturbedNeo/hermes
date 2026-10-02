import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/chat/application/contracts/message_role.dart';
import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/chat/application/contracts/chat_tool_execution.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';
import 'package:hermes/features/chat/runtime/chat_application/message_store.dart';
import 'package:hermes/features/task/runtime/task_tool_execution_service.dart';
import 'package:hermes/platform/tool_service.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/platform/workspace_sandbox.dart';

void main() {
  test(
    'chat tool executor persists results without owning continuation',
    () async {
      final messageStore = MessageStore();
      final assistant = Bubble(
        id: 'assistant_1',
        role: MessageRole.assistant,
        text: '',
        reasoning: '',
        createdAt: DateTime(2026, 1, 1),
        tools: const {
          0: BubbleToolCall(
            id: 'call_1',
            name: 'missing_tool',
            arguments: '{}',
          ),
        },
      );
      messageStore.setMessages([assistant], currentId: assistant.id);
      final executor = ChatToolExecutionService(
        protocol: ToolProtocolAdapter(
          registry: ToolService(workspaceSandbox: WorkspaceSandbox()),
        ),
      );

      final results = <ChatToolExecutionResult>[];
      await executor.executePendingCalls(
        calls: [
          const ChatPendingToolCall(
            index: 0,
            id: 'call_1',
            name: 'missing_tool',
            arguments: ToolArguments(),
          ),
        ],
        workspace: null,
        cancellationToken: CancellationToken(),
        onResult: results.add,
      );

      expect(results, hasLength(1));
      final result = results.single.result;
      expect(result, isA<ToolFailure>());
      expect((result as ToolFailure).code, 'unknown_tool');
      expect(messageStore.currentMessage?.tools[0]?.result, isNull);
    },
  );

  test('task tool executor derives artifacts only from successful calls', () {
    final executor = TaskToolExecutionService(
      protocol: ToolProtocolAdapter(
        registry: ToolService(workspaceSandbox: WorkspaceSandbox()),
      ),
      sandbox: WorkspaceSandbox(),
    );
    final task = TaskAggregate(
      id: 'task_1',
      title: 'Task',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    final step = TaskStep(
      id: 'step_1',
      title: 'Write artifact',
      objective: 'Write artifact.',
      instructions: const [],
      mayEditFiles: false,
      artifacts: [
        TaskArtifact(
          id: 'planned_1',
          path: '.agent/tasks/task_1/result.txt',
          taskId: task.id,
          stepId: 'step_1',
          kind: 'file',
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
      status: TaskStepStatus.pending,
    );
    final calls = [
      TaskToolCallRecord(
        id: 'call_1',
        stepId: step.id,
        runId: 'run_1',
        toolName: 'write_file',
        result: const {'path': '.agent/tasks/task_1/result.txt'},
        timestamp: DateTime(2026, 1, 1),
      ),
      TaskToolCallRecord(
        id: 'call_2',
        stepId: step.id,
        runId: 'run_1',
        toolName: 'write_file',
        outcome: TaskToolCallOutcome.failed,
        result: const {'path': '.agent/tasks/task_1/result.txt'},
        timestamp: DateTime(2026, 1, 1),
      ),
    ];

    final artifacts = executor.artifactsFromToolCalls(task.id, step, calls);

    expect(artifacts, hasLength(1));
    expect(artifacts.single.path, '.agent/tasks/task_1/result.txt');
    expect(artifacts.single.runId, 'run_1');
  });
}
