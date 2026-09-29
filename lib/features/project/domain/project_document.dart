/// Project-owned document identity and planning projection.
///
/// Execution records are exchanged through the project application boundary;
/// this value keeps the project domain independent from persistence adapters.
class ProjectDocument {
  const ProjectDocument({required this.id, this.title = ''});

  final String id;
  final String title;
}
