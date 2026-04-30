import 'package:hermes/core/models/system_prompt.dart';

class PromptAssembler {
  const PromptAssembler();

  PromptAssemblyResult assemble(PromptAssemblyRequest request) {
    final preset = request.preset;
    if (preset?.isLegacy == true) {
      return _assembleLegacy(preset!, request);
    }

    final byId = {
      for (final module in request.availableModules) module.id: module,
    };
    final diagnostics = <String>[];
    final requested = <String>{
      ...?preset?.baseModuleIds,
      ...request.selectedModuleIds,
      ...request.autoModuleIds,
    };

    final resolved = <String, PromptModule>{};
    final visiting = <String>{};

    void include(String id) {
      if (resolved.containsKey(id)) return;
      if (!visiting.add(id)) {
        diagnostics.add('Skipped circular module requirement: $id');
        return;
      }

      final module = byId[id];
      if (module == null) {
        diagnostics.add('Missing module: $id');
        visiting.remove(id);
        return;
      }

      for (final requiredId in module.requiredModuleIds) {
        include(requiredId);
      }

      resolved[id] = module;
      visiting.remove(id);
    }

    for (final id in requested) {
      include(id);
    }

    final omitted = <PromptModule>[];
    final kept = <String, PromptModule>{};
    final candidates = resolved.values.toList()..sort(_moduleCompare);

    for (final candidate in candidates) {
      final conflictId = kept.keys.where((id) {
        final keptModule = kept[id]!;
        return candidate.conflictingModuleIds.contains(id) ||
            keptModule.conflictingModuleIds.contains(candidate.id);
      }).firstOrNull;

      if (conflictId == null) {
        kept[candidate.id] = candidate;
        continue;
      }

      final existing = kept[conflictId]!;
      final winner = _conflictWinner(existing, candidate);
      final loser = winner.id == existing.id ? candidate : existing;

      if (winner.id == candidate.id) {
        kept.remove(existing.id);
        kept[candidate.id] = candidate;
      }
      omitted.add(loser);
      diagnostics.add(
        'Omitted "${loser.name}" because it conflicts with "${winner.name}".',
      );
    }

    final included = kept.values.toList()..sort(_moduleCompare);
    final parts = <String>[
      for (final module in included) _renderModule(module, request),
      if ((preset?.customInstructions.trim().isNotEmpty ?? false))
        'Custom instructions:\n${preset!.customInstructions.trim()}',
      if (request.currentUserRequest?.trim().isNotEmpty ?? false)
        'Current request:\n${request.currentUserRequest!.trim()}',
    ].where((part) => part.trim().isNotEmpty).toList();

    final text = parts.join('\n\n').trim();
    return PromptAssemblyResult(
      text: text,
      includedModules: included,
      omittedModules: omitted,
      diagnostics: diagnostics,
    );
  }

  PromptAssemblyResult _assembleLegacy(
    PromptPreset preset,
    PromptAssemblyRequest request,
  ) {
    final parts = <String>[
      preset.legacyFullPrompt?.trim() ?? '',
      if (preset.customInstructions.trim().isNotEmpty)
        'Custom instructions:\n${preset.customInstructions.trim()}',
      _workspaceContext(request),
      if (request.currentUserRequest?.trim().isNotEmpty ?? false)
        'Current request:\n${request.currentUserRequest!.trim()}',
    ].where((part) => part.trim().isNotEmpty).toList();

    return PromptAssemblyResult(
      text: parts.join('\n\n').trim(),
      includedModules: const [],
      omittedModules: const [],
      diagnostics: const ['Rendered legacy full prompt.'],
    );
  }

  String _renderModule(PromptModule module, PromptAssemblyRequest request) {
    return _interpolate(module.content.trim(), request);
  }

  String _workspaceContext(PromptAssemblyRequest request) {
    if (request.workspaceRootPath == null && !request.workspaceMissing) {
      return '';
    }

    if (request.workspaceMissing) {
      return 'A workspace was attached to this chat, but the folder is currently missing, so workspace tools are unavailable.';
    }

    return _interpolate(
      '''
This chat has an attached workspace. The workspace root is:
{{workspaceRoot}}

Workspace rules:
- Use workspace tools for file and folder operations.
- Only operate inside the attached workspace and use workspace-relative paths.
- Inspect relevant files before editing them.
- Prefer small, precise changes.
- Explain destructive file operations before performing them.
- Terminal commands are guarded and may be unavailable unless the user enables them for this chat.
'''
          .trim(),
      request,
    );
  }

  String _interpolate(String input, PromptAssemblyRequest request) {
    return input
        .replaceAll('{{workspaceRoot}}', request.workspaceRootPath ?? '')
        .replaceAll(
          '{{workspaceStatus}}',
          request.workspaceMissing ? 'missing' : 'available',
        )
        .replaceAll(
          '{{terminalApproved}}',
          request.commandExecutionApproved ? 'true' : 'false',
        )
        .replaceAll('{{currentRequest}}', request.currentUserRequest ?? '');
  }

  int _moduleCompare(PromptModule a, PromptModule b) {
    final byPriority = a.priority.compareTo(b.priority);
    if (byPriority != 0) return byPriority;
    final byCategory = a.category.toLowerCase().compareTo(
      b.category.toLowerCase(),
    );
    if (byCategory != 0) return byCategory;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (byName != 0) return byName;
    return a.id.compareTo(b.id);
  }

  PromptModule _conflictWinner(PromptModule a, PromptModule b) {
    final byPriority = a.priority.compareTo(b.priority);
    if (byPriority < 0) return a;
    if (byPriority > 0) return b;
    return a.id.compareTo(b.id) <= 0 ? a : b;
  }
}
