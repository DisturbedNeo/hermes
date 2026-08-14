import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/chat/content_normaliser.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/services/chat/message_store.dart';

extension AssistantOps on MessageStore {
  void appendToken(ChatToken token) => appendTokens([token]);

  void appendTokens(Iterable<ChatToken> tokens) {
    var current = currentMessage;
    if (current == null) return;

    final text = StringBuffer(current.text);
    final reasoning = StringBuffer(current.reasoning);
    var tools = current.tools;
    var changed = false;
    for (final token in tokens) {
      final tool = token.tool;
      final reasoningChunk = token.reasoning;
      final contentChunk = token.content;
      if (tool != null) {
        tools = toolCaller.applyDelta(
          messageId: current.id,
          delta: tool,
          currentTools: tools,
        );
        changed = true;
      } else if (reasoningChunk != null && reasoningChunk.isNotEmpty) {
        reasoning.write(reasoningChunk);
        changed = true;
      } else if (contentChunk != null && contentChunk.isNotEmpty) {
        text.write(contentChunk);
        changed = true;
      }
    }
    if (!changed) return;

    current = current.copyWith(
      text: text.toString(),
      reasoning: reasoning.toString(),
      tools: tools,
    );
    upsert(
      current.text.contains('</think>')
          ? ContentNormaliser.normalise(current)
          : current,
    );
  }

  void appendCurrentText(String chunk) {
    final current = currentMessage;
    if (chunk.isEmpty || current == null) return;
    final updated = current.copyWith(text: current.text + chunk);
    upsert(
      updated.text.contains('</think>')
          ? ContentNormaliser.normalise(updated)
          : updated,
    );
  }

  void appendCurrentReasoning(String chunk) {
    final current = currentMessage;
    if (chunk.isEmpty || current == null) return;
    upsert(current.copyWith(reasoning: current.reasoning + chunk));
  }

  void applyCurrentToolDelta(ToolCallDelta delta) {
    final current = currentMessage;
    if (current == null) return;
    final updatedTools = toolCaller.applyDelta(
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
          createdAt: DateTime.now(),
        ),
      );
    }
  }
}
