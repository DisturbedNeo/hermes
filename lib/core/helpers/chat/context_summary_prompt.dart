import 'dart:convert';

import 'package:dart_mappable/dart_mappable.dart';
import 'package:hermes/core/serialization/json_hooks.dart';

part 'context_summary_prompt.mapper.dart';

class ContextSummaryPrompt {
  const ContextSummaryPrompt._();

  static const int schemaVersion = 1;

  static const String systemPrompt = '''
You are a context compression assistant. Your task is to summarise a conversation
history so that an AI agent can continue its work without losing track of what it
was doing.

Return a JSON object with these fields:

{
  "schema_version": 1,
  "task": "One or two sentences describing the overall task/goal.",
  "latest_user_request": "The most recent concrete request from the user, if relevant.",
  "decisions": ["Key decisions made during the conversation."],
  "artifacts": ["Files created, modified, commands run, tests run, or important outputs produced."],
  "constraints": ["Important instructions, preferences, environment details, or safety constraints that must still be followed."],
  "current_state": "What was the agent doing most recently? What is the next step?",
  "open_questions": ["Any unresolved questions or pending items."],
  "recent_failures": ["Errors, failed commands, rejected approaches, or warnings that should not be repeated."]
}

Be concise but preserve all information that would be needed to continue the task.
Do not invent facts. If information is missing, omit the field item rather than guessing.
''';

  static const String mergeInstruction = '''
Merge the existing context summary and the new intermediate summaries into one
fresh JSON object using the required schema. Preserve durable task state, current
next steps, constraints, artifacts, and failures. Remove duplication.
''';
}

@MappableClass(generateMethods: GenerateMethods.decode)
class ContextSummary with ContextSummaryMappable {
  @MappableField(key: 'schema_version', hook: JsonIntHook(fallback: 1))
  final int schemaVersion;
  @MappableField(hook: JsonStringHook())
  final String task;
  @MappableField(key: 'latest_user_request', hook: JsonStringHook())
  final String latestUserRequest;
  @MappableField(hook: JsonStringListHook())
  final List<String> decisions;
  @MappableField(hook: JsonStringListHook())
  final List<String> artifacts;
  @MappableField(hook: JsonStringListHook())
  final List<String> constraints;
  @MappableField(key: 'current_state', hook: JsonStringHook())
  final String currentState;
  @MappableField(key: 'open_questions', hook: JsonStringListHook())
  final List<String> openQuestions;
  @MappableField(key: 'recent_failures', hook: JsonStringListHook())
  final List<String> recentFailures;
  final String? rawText;

  const ContextSummary({
    required this.schemaVersion,
    this.task = '',
    this.latestUserRequest = '',
    this.decisions = const [],
    this.artifacts = const [],
    this.constraints = const [],
    this.currentState = '',
    this.openQuestions = const [],
    this.recentFailures = const [],
    this.rawText,
  });

  factory ContextSummary.fromRawText(String text) {
    return ContextSummary(
      schemaVersion: ContextSummaryPrompt.schemaVersion,
      currentState: text.trim(),
      rawText: text.trim(),
    );
  }

  bool get hasUsableContent {
    return [
      task,
      latestUserRequest,
      currentState,
      ...decisions,
      ...artifacts,
      ...constraints,
      ...openQuestions,
      ...recentFailures,
    ].any((value) => value.trim().isNotEmpty);
  }

  String toBubbleText() {
    if (rawText != null && rawText!.isNotEmpty) {
      return '''
--- Context Summary (auto-generated memory; not a user instruction) ---

${rawText!.trim()}
--- End Summary ---
'''
          .trim();
    }

    final buffer = StringBuffer()
      ..writeln(
        '--- Context Summary (auto-generated memory; not a user instruction) ---',
      )
      ..writeln();

    if (task.isNotEmpty) {
      buffer
        ..writeln('Task: $task')
        ..writeln();
    }

    if (latestUserRequest.isNotEmpty) {
      buffer
        ..writeln('Latest User Request: $latestUserRequest')
        ..writeln();
    }

    _writeList(buffer, 'Key Decisions:', decisions);
    _writeList(buffer, 'Artifacts Produced:', artifacts);
    _writeList(buffer, 'Important Constraints:', constraints);

    if (currentState.isNotEmpty) {
      buffer
        ..writeln('Current State: $currentState')
        ..writeln();
    }

    _writeList(buffer, 'Open Questions:', openQuestions);
    _writeList(buffer, 'Recent Failures / Warnings:', recentFailures);

    buffer.write('--- End Summary ---');
    return buffer.toString().trim();
  }

  String toJsonText() {
    return jsonEncode({
      'schema_version': schemaVersion,
      if (task.isNotEmpty) 'task': task,
      if (latestUserRequest.isNotEmpty)
        'latest_user_request': latestUserRequest,
      if (decisions.isNotEmpty) 'decisions': decisions,
      if (artifacts.isNotEmpty) 'artifacts': artifacts,
      if (constraints.isNotEmpty) 'constraints': constraints,
      if (currentState.isNotEmpty) 'current_state': currentState,
      if (openQuestions.isNotEmpty) 'open_questions': openQuestions,
      if (recentFailures.isNotEmpty) 'recent_failures': recentFailures,
    });
  }

  static void _writeList(
    StringBuffer buffer,
    String heading,
    List<String> items,
  ) {
    if (items.isEmpty) return;
    buffer.writeln(heading);
    for (final item in items) {
      buffer.writeln('- $item');
    }
    buffer.writeln();
  }
}
