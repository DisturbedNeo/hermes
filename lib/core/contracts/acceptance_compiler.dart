import 'package:hermes/core/contracts/acceptance.dart';

/// A deterministic, feature-neutral representation of one compiled verifier.
/// Project and Task adapters turn this representation into their own internal
/// gate and evidence objects; neither adapter reinterprets planner input.
class CompiledAcceptanceVerifier {
  const CompiledAcceptanceVerifier({
    required this.acceptanceRef,
    required this.verifierIndex,
    required this.kind,
    required this.required,
    required this.statement,
    required this.criterionIds,
    required this.params,
  });

  final String acceptanceRef;
  final int verifierIndex;
  final AcceptanceVerifierKind kind;
  final bool required;
  final String statement;
  final List<String> criterionIds;
  final Map<String, dynamic> params;

  String get gateKind => switch (kind) {
    AcceptanceVerifierKind.command => 'command_passes',
    AcceptanceVerifierKind.artifact => 'artifact_exists',
    AcceptanceVerifierKind.review => 'model_review',
    AcceptanceVerifierKind.approval => 'human_approval',
  };

  List<String> get gateKinds => kind == AcceptanceVerifierKind.artifact
      ? const ['artifact_exists', 'artifact_nonempty']
      : [gateKind];

  String get evidenceKind => switch (kind) {
    AcceptanceVerifierKind.command => 'command',
    AcceptanceVerifierKind.artifact => 'artifact',
    AcceptanceVerifierKind.review => 'gate',
    AcceptanceVerifierKind.approval => 'user_approval',
  };
}

class AcceptanceCompilation {
  const AcceptanceCompilation({required this.verifiers});

  final List<CompiledAcceptanceVerifier> verifiers;

  List<String> get criterionIds =>
      {for (final verifier in verifiers) ...verifier.criterionIds}.toList();

  List<String> get statements =>
      {for (final verifier in verifiers) verifier.statement}.toList();
}

class AcceptanceContractException implements Exception {
  const AcceptanceContractException({
    required this.code,
    required this.path,
    required this.message,
  });

  final String code;
  final String path;
  final String message;

  @override
  String toString() => '$code ($path): $message';
}

/// The one compiler for planner-authored acceptance.
///
/// It performs the contract checks that must be identical at both planning
/// boundaries and emits only deterministic internal verifier descriptions.
class AcceptanceCompiler {
  const AcceptanceCompiler();

  AcceptanceCompilation compile(
    Iterable<AcceptanceItem> items, {
    bool requireProjectCriteria = false,
    String path = 'acceptance',
    String? Function(String command)? commandSafetyValidator,
  }) {
    final compiled = <CompiledAcceptanceVerifier>[];
    final refs = <String>{};
    var itemIndex = 0;
    for (final item in items) {
      final itemPath = '$path[$itemIndex]';
      final ref = item.ref.trim();
      final statement = item.statement.trim();
      if (ref.isEmpty) {
        _throw(
          'missing_acceptance_ref',
          '$itemPath.ref',
          'Acceptance refs must be non-empty.',
        );
      }
      if (!refs.add(ref)) {
        _throw(
          'duplicate_acceptance_ref',
          '$itemPath.ref',
          'Acceptance refs must be unique within a task.',
        );
      }
      if (statement.isEmpty) {
        _throw(
          'missing_acceptance_statement',
          '$itemPath.statement',
          'Acceptance statements must be non-empty.',
        );
      }
      if (item.verifiers.isEmpty) {
        _throw(
          'missing_acceptance_verifier',
          '$itemPath.verifiers',
          'Each acceptance item needs at least one verifier.',
        );
      }
      if (requireProjectCriteria && item.criterionIds.isEmpty) {
        _throw(
          'missing_acceptance_criterion',
          '$itemPath.criterion_refs',
          'Project acceptance must link to at least one project criterion.',
        );
      }
      if (!item.verifiers.any((verifier) => verifier.required)) {
        _throw(
          'missing_required_verifier',
          '$itemPath.verifiers',
          'Each acceptance item needs at least one required verifier.',
        );
      }
      for (
        var verifierIndex = 0;
        verifierIndex < item.verifiers.length;
        verifierIndex++
      ) {
        final verifier = item.verifiers[verifierIndex];
        final verifierPath = '$itemPath.verifiers[$verifierIndex]';
        if (!verifier.hasConfiguration) {
          _throw(
            'invalid_acceptance_verifier',
            verifierPath,
            'Verifier configuration does not match its kind.',
          );
        }
        if (verifier.kind == AcceptanceVerifierKind.command &&
            commandSafetyValidator != null) {
          final reason = commandSafetyValidator(verifier.command!.trim());
          if (reason != null && reason.trim().isNotEmpty) {
            _throw(
              'blocked_command',
              '$verifierPath.command',
              'Verification command is rejected by terminal policy: $reason',
            );
          }
        }
        _validateWorkspacePath(
          verifier.workingDirectory,
          '$verifierPath.working_directory',
          allowEmpty: false,
        );
        if (verifier.kind == AcceptanceVerifierKind.artifact) {
          _validateWorkspacePath(
            verifier.path!,
            '$verifierPath.path',
            allowEmpty: false,
          );
        }
        compiled.add(
          CompiledAcceptanceVerifier(
            acceptanceRef: ref,
            verifierIndex: verifierIndex,
            kind: verifier.kind,
            required: verifier.required,
            statement: statement,
            criterionIds: List.unmodifiable(item.criterionIds),
            params: {
              'acceptance_ref': ref,
              'verifier_index': verifierIndex,
              if (verifier.kind == AcceptanceVerifierKind.review)
                'prompt': statement,
              if (verifier.command != null) 'command': verifier.command,
              if (verifier.command != null)
                'working_directory': verifier.workingDirectory,
              if (verifier.path != null) 'path': verifier.path,
              if (verifier.path != null) 'kind': verifier.artifactKind,
              if (verifier.description != null)
                'description': verifier.description,
            },
          ),
        );
      }
      itemIndex++;
    }
    return AcceptanceCompilation(verifiers: List.unmodifiable(compiled));
  }

  Never _throw(String code, String path, String message) =>
      throw AcceptanceContractException(
        code: code,
        path: path,
        message: message,
      );

  void _validateWorkspacePath(
    String value,
    String fieldPath, {
    required bool allowEmpty,
  }) {
    final normalized = value.trim();
    if (!allowEmpty && normalized.isEmpty) {
      _throw(
        'invalid_workspace_path',
        fieldPath,
        'Workspace paths must be non-empty and relative.',
      );
    }
    if (normalized.startsWith('/') ||
        normalized.startsWith('\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(normalized) ||
        normalized.split('/').contains('..') ||
        normalized.split('\\').contains('..')) {
      _throw(
        'unsafe_workspace_path',
        fieldPath,
        'Workspace paths must remain inside the workspace.',
      );
    }
  }
}
