import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/shared_kernel/message_role.dart';
import 'package:hermes/shared_kernel/uuid.dart';
import 'package:hermes/shared_kernel/bubble.dart';
import 'package:hermes/features/chat/domain/chat_state.dart';

void main() {
  final systemPrompt = Bubble(
    id: uuid.v7(),
    role: MessageRole.system,
    text: 'system',
    reasoning: '',
    createdAt: DateTime(2026),
  );

  test('state snapshots defensively copy user-visible collections', () {
    final input = <Bubble>[systemPrompt];
    final state = ChatState.initial('tab-1', systemPrompt);
    final copied = state.copyWith(messages: input);

    input.clear();
    expect(copied.messages, hasLength(1));
    expect(() => copied.messages.add(systemPrompt), throwsUnsupportedError);
  });

  test('reducer prevents cancellation and busy/error contradictions', () {
    const reducer = ChatStateReducer();
    final idle = ChatState.initial('tab-1', systemPrompt);
    final cancelledWhileIdle = reducer.requestTaskCancellation(idle);
    expect(cancelledWhileIdle.taskCancellationRequested, isFalse);

    final running = reducer.dispatchTaskBusy(idle, true);
    final cancelled = reducer.requestTaskCancellation(running);
    expect(cancelled.taskBusy, isTrue);
    expect(cancelled.taskCancellationRequested, isTrue);

    final failed = reducer.dispatchTaskError(cancelled, StateError('failed'));
    expect(failed.taskBusy, isFalse);
    expect(failed.taskCancellationRequested, isFalse);
    expect(failed.taskError, isA<StateError>());
  });
}
