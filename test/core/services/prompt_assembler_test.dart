import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/services/prompt_assembler.dart';

void main() {
  group('PromptAssembler', () {
    const assembler = PromptAssembler();

    test('sorts modules deterministically by priority, category, and name', () {
      final result = assembler.assemble(
        PromptAssemblyRequest(
          preset: _preset(base: const ['b', 'a', 'c']),
          availableModules: [
            _module(id: 'c', name: 'Zulu', category: 'Style', priority: 20),
            _module(id: 'b', name: 'Alpha', category: 'Core', priority: 10),
            _module(id: 'a', name: 'Beta', category: 'Core', priority: 10),
          ],
        ),
      );

      expect(result.includedModules.map((m) => m.id), ['b', 'a', 'c']);
      expect(result.text, contains('Alpha content'));
      expect(
        result.text.indexOf('Alpha content'),
        lessThan(result.text.indexOf('Beta content')),
      );
    });

    test('adds required modules recursively and deduplicates them', () {
      final result = assembler.assemble(
        PromptAssemblyRequest(
          preset: _preset(base: const ['mode']),
          availableModules: [
            _module(id: 'core', priority: 0),
            _module(id: 'policy', priority: 5, required: const ['core']),
            _module(id: 'mode', priority: 10, required: const ['policy']),
          ],
        ),
      );

      expect(result.includedModules.map((m) => m.id), [
        'core',
        'policy',
        'mode',
      ]);
      expect(result.diagnostics, isEmpty);
    });

    test('includes optional modules only when selected', () {
      final result = assembler.assemble(
        PromptAssemblyRequest(
          preset: _preset(
            base: const ['coding'],
            optional: const ['csharp', 'rust'],
          ),
          availableModules: [
            _module(id: 'coding', content: 'You are a senior engineer.'),
            _module(id: 'csharp', content: 'You specialise in C#.'),
            _module(id: 'rust', content: 'You specialise in Rust.'),
          ],
          selectedModuleIds: const ['csharp'],
        ),
      );

      expect(result.text, contains('You are a senior engineer.'));
      expect(result.text, contains('You specialise in C#.'));
      expect(result.text, isNot(contains('You specialise in Rust.')));
      expect(result.includedModules.map((module) => module.id), [
        'coding',
        'csharp',
      ]);
    });

    test('resolves conflicts by lower priority then id', () {
      final result = assembler.assemble(
        PromptAssemblyRequest(
          preset: _preset(base: const ['strict', 'brief']),
          availableModules: [
            _module(
              id: 'strict',
              name: 'Strict',
              priority: 20,
              conflicts: const ['brief'],
            ),
            _module(
              id: 'brief',
              name: 'Brief',
              priority: 10,
              conflicts: const ['strict'],
            ),
          ],
        ),
      );

      expect(result.includedModules.map((m) => m.id), ['brief']);
      expect(result.omittedModules.map((m) => m.id), ['strict']);
      expect(result.diagnostics.single, contains('conflicts'));
    });

    test(
      'renders custom instructions, context variables, and current request',
      () {
        final result = assembler.assemble(
          PromptAssemblyRequest(
            preset: _preset(
              base: const ['workspace'],
              custom: 'Use concise bullet points.',
            ),
            availableModules: [
              _module(
                id: 'workspace',
                content:
                    'Workspace: {{workspaceRoot}}; terminal={{terminalApproved}}',
              ),
            ],
            workspaceRootPath: '/repo',
            commandExecutionApproved: true,
            currentUserRequest: 'Summarise this file.',
          ),
        );

        expect(result.text, contains('Workspace: /repo; terminal=true'));
        expect(result.text, contains('Custom instructions:'));
        expect(result.text, contains('Use concise bullet points.'));
        expect(result.text, contains('Current request:'));
        expect(result.text, contains('Summarise this file.'));
      },
    );

    test('renders legacy full prompts with workspace context', () {
      final result = assembler.assemble(
        PromptAssemblyRequest(
          preset: _preset(legacy: 'Legacy prompt.'),
          availableModules: const [],
          workspaceRootPath: '/repo',
        ),
      );

      expect(result.text, startsWith('Legacy prompt.'));
      expect(result.text, contains('This chat has an attached workspace.'));
      expect(result.diagnostics.single, contains('legacy'));
    });
  });
}

PromptPreset _preset({
  List<String> base = const [],
  List<String> optional = const [],
  String custom = '',
  String? legacy,
}) {
  final now = DateTime(2026);
  return PromptPreset(
    id: 'preset',
    name: 'Preset',
    baseModuleIds: base,
    optionalModuleIds: optional,
    customInstructions: custom,
    legacyFullPrompt: legacy,
    isBuiltIn: false,
    createdAt: now,
    updatedAt: now,
  );
}

PromptModule _module({
  required String id,
  String? name,
  String category = 'Core',
  String? content,
  int priority = 100,
  List<String> required = const [],
  List<String> conflicts = const [],
}) {
  final now = DateTime(2026);
  final resolvedName = name ?? id;
  return PromptModule(
    id: id,
    name: resolvedName,
    category: category,
    content: content ?? '$resolvedName content',
    priority: priority,
    isBuiltIn: false,
    requiredModuleIds: required,
    conflictingModuleIds: conflicts,
    createdAt: now,
    updatedAt: now,
  );
}
