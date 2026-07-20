import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/subagent_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

void main() {
  test('read_file request mode returns only assistant content', () async {
    final root = await Directory.systemTemp.createTemp('hermes_subagent_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    await File('${root.path}/notes.txt').writeAsString('visible facts');

    final client = _FakeChatClient(
      const ChatCompletionResponse(
        content:
            '<think>internal content reasoning</think>\n  extracted facts  ',
        reasoning: 'internal extraction reasoning',
      ),
    );
    final service = ToolService(workspaceSandbox: WorkspaceSandbox())
      ..setSubagentService(SubagentService(chatClientFactory: () => client));

    final result = await service.execute(
      toolId: 'read_file',
      argumentsJson: jsonEncode({
        'path': 'notes.txt',
        'request': 'Return the facts.',
      }),
      context: WorkspaceToolContext(
        workspace: WorkspaceAttachment.fromPath(root.path),
      ),
    );

    final decoded = jsonDecode(result) as Map<String, dynamic>;
    expect(decoded.keys, ['extracted']);
    expect(decoded['extracted'], 'extracted facts');
    expect(result, isNot(contains('internal extraction reasoning')));
    expect(result, isNot(contains('internal content reasoning')));
    expect(client.seenExtraParams?['chat_template_kwargs'], {
      'enable_thinking': false,
      'reasoning_budget': 0,
    });
  });

  test(
    'read_file request mode does not fall back to reasoning content',
    () async {
      final root = await Directory.systemTemp.createTemp('hermes_subagent_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      await File('${root.path}/notes.txt').writeAsString('visible facts');

      final service = ToolService(workspaceSandbox: WorkspaceSandbox())
        ..setSubagentService(
          SubagentService(
            chatClientFactory: () => _FakeChatClient(
              const ChatCompletionResponse(
                content: '',
                reasoning: 'internal extraction reasoning',
              ),
            ),
          ),
        );

      final result = await service.execute(
        toolId: 'read_file',
        argumentsJson: jsonEncode({
          'path': 'notes.txt',
          'request': 'Return the facts.',
        }),
        context: WorkspaceToolContext(
          workspace: WorkspaceAttachment.fromPath(root.path),
        ),
      );

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['extracted'], '');
      expect(result, isNot(contains('internal extraction reasoning')));
    },
  );
}

class _FakeChatClient extends ChatClient {
  _FakeChatClient(this._response)
    : super(baseUrl: 'http://localhost', model: 'test');

  final ChatCompletionResponse _response;
  Map<String, dynamic>? seenExtraParams;

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) async {
    seenExtraParams = extraParams;
    return _response;
  }

  @override
  void dispose() {}
}
