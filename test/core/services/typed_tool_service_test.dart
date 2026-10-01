import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/platform/tool_service.dart';
import 'package:hermes/platform/workspace_sandbox.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';

void main() {
  late Directory workspace;
  late ToolService tools;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('hermes-tools-');
    tools = ToolService(workspaceSandbox: WorkspaceSandbox());
  });

  tearDown(() async {
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  test('decodes typed requests and converts successful tool results', () async {
    final request = const ToolRequest(
      toolId: 'calculator',
      arguments: ToolArguments({'paramA': 2, 'paramB': 3, 'operator': '+'}),
    );
    final result = await tools.executeTyped(request);

    expect(result, isA<ToolSuccess>());
    expect((result as ToolSuccess).value['result'], 5);
  });

  test(
    'protocol adapter rejects malformed input and preserves failures',
    () async {
      final adapter = ToolProtocolAdapter(registry: tools);
      expect(
        await adapter.execute(toolId: 'calculator', argumentsJson: '[]'),
        contains('invalid_tool_arguments'),
      );
    },
  );

  test(
    'enforces workspace permission and cancellation before execution',
    () async {
      final denied = await tools.executeTyped(
        const ToolRequest(toolId: 'read_file'),
      );
      expect(denied, isA<ToolFailure>());
      expect((denied as ToolFailure).code, 'permission_denied');

      final token = CancellationToken();
      await token.cancel();
      final cancelled = await tools.executeTyped(
        ToolRequest(
          toolId: 'calculator',
          arguments: const ToolArguments({
            'paramA': 1,
            'paramB': 2,
            'operator': '+',
          }),
          context: ToolContext(
            permission: ToolPermission.none,
            cancellationToken: token,
          ),
        ),
      );
      expect(cancelled, isA<ToolFailure>());
      expect((cancelled as ToolFailure).code, 'cancelled');
    },
  );

  test('workspace tools require an approved typed workspace context', () async {
    final result = await tools.executeTyped(
      ToolRequest(
        toolId: 'read_file',
        arguments: const ToolArguments({'path': 'missing.txt'}),
        context: ToolContext(
          workspace: ToolWorkspace(rootPath: '/does/not/exist'),
          permission: ToolPermission.readWorkspace,
        ),
      ),
    );
    expect(result, isA<ToolFailure>());
    expect((result as ToolFailure).code, isNot('permission_denied'));
  });
}
