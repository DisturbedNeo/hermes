import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/shared_kernel/message_role.dart';
import 'package:hermes/shared_kernel/bubble.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/shared_kernel/cancellation.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';
import 'package:hermes/features/chat/runtime/chat_application/message_store.dart';
import 'package:hermes/features/task/runtime/task_tool_execution_service.dart';
import 'package:hermes/platform/tool_service.dart';
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
        toolService: ToolService(workspaceSandbox: WorkspaceSandbox()),
        messageStore: messageStore,
      );

      final updated = await executor.executePendingCalls(
        calls: [MapEntry(0, assistant.tools[0]!)],
        workspace: null,
        cancellationToken: CancellationToken(),
      );

      expect(updated, isNotNull);
      final result = jsonDecode(updated!.tools[0]!.result!);
      expect(result['error_code'], 'unknown_tool');
      expect(messageStore.currentMessage?.tools[0]?.result, isNotNull);
    },
  );

  test('task tool executor derives artifacts only from successful calls', () {
    final executor = TaskToolExecutionService(
      toolService: ToolService(workspaceSandbox: WorkspaceSandbox()),
      sandbox: WorkspaceSandbox(),
    );
    final task = Task(
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
