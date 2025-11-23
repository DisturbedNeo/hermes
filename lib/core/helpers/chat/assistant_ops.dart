import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/services/chat/message_store.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';

extension AssistantOps on MessageStore {
  void appendToken(ChatToken token) {
    if (token.tool != null) {
      applyCurrentToolDelta(token.tool!);
    } else if (token.reasoning != null) {
      appendCurrentReasoning(token.reasoning!);
    } else if (token.content != null) {
      appendCurrentText(token.content!);
    }
  }

  void appendCurrentText(String chunk) {
    final current = currentMessage;
    if (chunk.isEmpty || current == null) return;
    upsert(current.copyWith(text: current.text + chunk));
  }

  void appendCurrentReasoning(String chunk) {
    final current = currentMessage;
    if (chunk.isEmpty || current == null) return;
    upsert(current.copyWith(reasoning: current.reasoning + chunk));
  }

  void applyCurrentToolDelta(ToolCallDelta delta) {
    final current = currentMessage;
    if (current == null) return;
    final updatedTools = ToolCaller.applyDelta(
      messageId: current.id,
      delta: delta,
      currentTools: current.tools,
    );
    upsert(current.copyWith(tools: updatedTools));
  }

  void appendCurrentError(Object e) {
    if (currentMessage == null) return;

    final err = '\n\n Something went wrong: \n$e';

    if (currentMessage!.role == MessageRole.assistant) {
      upsert(currentMessage!.copyWith(text: currentMessage!.text + err));
    } else {
      upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: err,
          reasoning: '',
        ),
      );
    }
  }
}
