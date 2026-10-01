import 'package:dart_mappable/dart_mappable.dart';
import 'package:path/path.dart' as path;

part 'workspace_discovery_profile.mapper.dart';

@MappableClass(ignoreNull: true)
class WorkspaceDiscoveryProfile with WorkspaceDiscoveryProfileMappable {
  final String workspaceName;
  final List<String> treePaths;
  final List<WorkspaceFileExcerpt> highSignalFiles;
  final String? packageName;
  final Map<String, String> scripts;
  final List<String> dependencies;
  final List<String> languages;
  final List<String> frameworks;
  final bool treeTruncated;
  final bool contentTruncated;
  final int omittedPathCount;
  final List<WorkspaceRequiredContextIssue> requiredContextIssues;

  const WorkspaceDiscoveryProfile({
    required this.workspaceName,
    this.treePaths = const [],
    this.highSignalFiles = const [],
    this.packageName,
    this.scripts = const {},
    this.dependencies = const [],
    this.languages = const [],
    this.frameworks = const [],
    this.treeTruncated = false,
    this.contentTruncated = false,
    this.omittedPathCount = 0,
    this.requiredContextIssues = const [],
  });

  List<String> get rootEntries => treePaths
      .map(
        (item) =>
            item.endsWith('/') ? item.substring(0, item.length - 1) : item,
      )
      .where((item) => path.split(item).length == 1)
      .toList();
}

@MappableClass()
class WorkspaceRequiredContextIssue with WorkspaceRequiredContextIssueMappable {
  final String path;
  final String code;
  final String message;

  const WorkspaceRequiredContextIssue({
    required this.path,
    required this.code,
    required this.message,
  });
}

@MappableClass()
class WorkspaceFileExcerpt with WorkspaceFileExcerptMappable {
  final String path;
  final String content;
  final bool truncated;

  const WorkspaceFileExcerpt({
    required this.path,
    required this.content,
    this.truncated = false,
  });
}
