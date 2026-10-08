import 'package:dart_mappable/dart_mappable.dart';

part 'acceptance.mapper.dart';

/// The kinds of proof that can satisfy one acceptance item.
@MappableEnum(defaultValue: AcceptanceVerifierKind.command)
enum AcceptanceVerifierKind { command, artifact, review, approval }

extension AcceptanceVerifierKindWire on AcceptanceVerifierKind {
  String get wire => name;
}

/// A verifier supplied by the planner and compiled by Hermes into internal
/// gates and evidence expectations.
@MappableClass(ignoreNull: true)
class AcceptanceVerifier with AcceptanceVerifierMappable {
  const AcceptanceVerifier({
    required this.kind,
    this.required = true,
    this.command,
    this.workingDirectory = '.',
    this.path,
    this.artifactKind = 'file',
    this.description,
  });

  final AcceptanceVerifierKind kind;
  final bool required;
  final String? command;
  final String workingDirectory;
  final String? path;
  final String artifactKind;
  final String? description;

  bool get hasConfiguration => switch (kind) {
    AcceptanceVerifierKind.command => command?.trim().isNotEmpty == true,
    AcceptanceVerifierKind.artifact => path?.trim().isNotEmpty == true,
    AcceptanceVerifierKind.review || AcceptanceVerifierKind.approval => true,
  };
}

/// Canonical task acceptance. Criterion IDs are resolved by project planning;
/// an empty list means that the item is intentionally task-local.
@MappableClass(ignoreNull: true)
class AcceptanceItem with AcceptanceItemMappable {
  const AcceptanceItem({
    required this.ref,
    required this.statement,
    this.criterionIds = const [],
    this.verifiers = const [],
  });

  final String ref;
  final String statement;
  final List<String> criterionIds;
  final List<AcceptanceVerifier> verifiers;
}
