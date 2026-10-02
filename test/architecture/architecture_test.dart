import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:flutter_test/flutter_test.dart';

/// Authoritative production architecture gate. It parses every production
/// source so new files cannot silently join a broad catch-all module.
const _modules = {'app', 'core', 'features', 'platform'};
const _featureLayers = {
  'application',
  'domain',
  'infrastructure',
  'presentation',
  'runtime',
};

class _Directive {
  const _Directive(this.uri, this.line);

  final String uri;
  final int line;
}

class _Source {
  const _Source(this.path, this.text, this.imports, this.exports, this.parts);

  final String path;
  final String text;
  final List<_Directive> imports;
  final List<_Directive> exports;
  final List<_Directive> parts;

  String get module =>
      path == 'lib/app_dependencies.dart' || path == 'lib/main.dart'
      ? 'app'
      : path.substring('lib/'.length).split('/').first;
  String? get feature {
    final segments = path.substring('lib/'.length).split('/');
    return segments.first == 'features' && segments.length > 1
        ? segments[1]
        : null;
  }

  String? get layer {
    final segments = path.substring('lib/'.length).split('/');
    if (segments.first != 'features' || segments.length < 3) return null;
    return _featureLayers.contains(segments[2]) ? segments[2] : null;
  }
}

class _Graph {
  const _Graph(this.sources);

  final List<_Source> sources;
  Map<String, _Source> get byPath => {
    for (final source in sources) source.path: source,
  };
}

int _line(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset)).length + 1;

List<_Directive> _directives(String text, String keyword) {
  final result = <_Directive>[];
  final unit = parseString(content: text).unit;
  for (final directive in unit.directives) {
    final uri = switch (keyword) {
      'import' when directive is ImportDirective => directive.uri.stringValue,
      'export' when directive is ExportDirective => directive.uri.stringValue,
      'part' when directive is PartDirective => directive.uri.stringValue,
      _ => null,
    };
    if (uri != null) {
      result.add(_Directive(uri, _line(text, directive.offset)));
    }
  }
  return result;
}

Iterable<String> _interfaceBodies(String text) sync* {
  final declaration = RegExp(
    r'abstract\s+interface\s+class\s+\w+[^\{]*\{',
    multiLine: true,
  );
  for (final match in declaration.allMatches(text)) {
    var depth = 0;
    var end = match.end;
    for (var i = match.end - 1; i < text.length; i++) {
      final character = text[i];
      if (character == '{') depth++;
      if (character == '}') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    yield text.substring(match.end, end);
  }
}

String _resolve(String source, String uri) {
  if (uri.startsWith('package:hermes/')) {
    return 'lib/${uri.substring('package:hermes/'.length)}';
  }
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return '';
  final parts = source.split('/')..removeLast();
  for (final segment in uri.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(segment);
    }
  }
  return parts.join('/');
}

Future<_Graph> _readGraph() async {
  final sources = <_Source>[];
  await for (final entity in Directory('lib').list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll('\\', '/');
    final text = await entity.readAsString();
    sources.add(
      _Source(
        path,
        text,
        _directives(text, 'import'),
        _directives(text, 'export'),
        _directives(text, 'part'),
      ),
    );
  }
  sources.sort((a, b) => a.path.compareTo(b.path));
  return _Graph(sources);
}

String _analysisSdkPath() {
  final configured = Platform.environment['DART_SDK'];
  if (configured != null && Directory(configured).existsSync()) {
    return Directory(configured).resolveSymbolicLinksSync();
  }

  final executable = File(Platform.resolvedExecutable).absolute;
  final executableParent = executable.parent;
  if (executableParent.path.endsWith('/bin') &&
      executableParent.parent.path.endsWith('/dart-sdk')) {
    return executableParent.parent.path;
  }
  const engineMarker = '/bin/cache/artifacts/engine/';
  final engineIndex = executable.path.indexOf(engineMarker);
  if (engineIndex >= 0) {
    final flutterRoot = executable.path.substring(0, engineIndex);
    final sdk = Directory('$flutterRoot/bin/cache/dart-sdk');
    if (sdk.existsSync()) return sdk.resolveSymbolicLinksSync();
  }

  for (final path in Platform.environment['PATH']!.split(
    Platform.pathSeparator,
  )) {
    final flutter = File('$path/flutter');
    if (flutter.existsSync()) {
      final sdk = Directory('$path/../cache/dart-sdk');
      if (sdk.existsSync()) return sdk.resolveSymbolicLinksSync();
    }
  }
  throw StateError(
    'Unable to locate the Dart SDK for resolved architecture checks',
  );
}

Map<String, Set<String>> _importGraph(_Graph graph) {
  final result = <String, Set<String>>{
    for (final source in graph.sources) source.path: <String>{},
  };
  for (final source in graph.sources) {
    for (final directive in [...source.imports, ...source.exports]) {
      final target = _resolve(source.path, directive.uri);
      if (graph.byPath.containsKey(target)) result[source.path]!.add(target);
    }
  }
  return result;
}

List<String> _cycles(Map<String, Set<String>> graph) {
  final active = <String>{};
  final visited = <String>{};
  final stack = <String>[];
  final result = <String>[];

  void visit(String node) {
    if (active.contains(node)) {
      final start = stack.indexOf(node);
      result.add([...stack.sublist(start), node].join(' -> '));
      return;
    }
    if (!visited.add(node)) return;
    active.add(node);
    stack.add(node);
    for (final target in graph[node] ?? const <String>{}) {
      visit(target);
    }
    stack.removeLast();
    active.remove(node);
  }

  for (final node in graph.keys) {
    visit(node);
  }
  return result;
}

bool _isPort(_Source source) =>
    source.path.endsWith('_port.dart') || source.path.endsWith('_ports.dart');

bool _isProtocolAdapter(_Source source) =>
    source.path.endsWith('_protocol_adapter.dart');

String? _architecturalLayer(_Source source) =>
    source.layer ?? (_isPort(source) ? 'application' : null);

/// These are deliberately explicit public-facade edges. The application
/// facade is the stable API and the runtime implementation remains below it;
/// only these named facades may cross that boundary.
const _publicFacadeEdges = <String>{
  'lib/features/chat/application/chat_controller.dart -> '
      'lib/features/chat/runtime/chat_controller.dart',
  'lib/features/chat/application/chat_workspace_controller.dart -> '
      'lib/features/chat/runtime/chat_workspace_controller.dart',
  'lib/features/project/application/project_application/project_application.dart -> '
      'lib/features/project/runtime/project_application.dart',
  'lib/features/task/application/task_application/task_controller.dart -> '
      'lib/features/task/runtime/task_controller.dart',
  'lib/features/model/domain/model_completion.dart -> '
      'lib/features/model/application/model_completion.dart',
  'lib/features/model/domain/model_configuration.dart -> '
      'lib/features/model/application/model_configuration.dart',
  'lib/features/project/application/contracts/project_state_models.dart -> '
      'lib/features/persistence/infrastructure/dto/project_state_models.dart',
  'lib/features/task/application/contracts/task_state_models.dart -> '
      'lib/features/persistence/infrastructure/dto/task_state_models.dart',
};

String _edgeKey(_Source source, _Source target) =>
    '${source.path} -> ${target.path}';

bool _allowed(_Source source, _Source target) {
  if (source.module == 'app') return true;
  if (target.module == 'app') return false;
  if (source.module == 'core') return target.module == 'core';
  if (source.module == 'platform') {
    return target.module == 'platform' ||
        target.module == 'core' ||
        (target.module == 'features' && target.layer == 'application');
  }

  final sourceLayer = _architecturalLayer(source);
  final targetLayer = _architecturalLayer(target);

  final edge = _edgeKey(source, target);
  if (_publicFacadeEdges.contains(edge)) return true;

  // Presentation must consume application/domain projections and ports. It
  // must not reach around the application boundary into runtime or adapters.
  if (source.layer == 'presentation' &&
      (target.layer == 'runtime' || target.layer == 'infrastructure')) {
    return false;
  }

  // Application/runtime code may use named protocol adapters, but concrete
  // persistence, process, filesystem, database, and model-server adapters
  // must enter through typed application ports.
  if ((sourceLayer == 'application' || sourceLayer == 'runtime') &&
      targetLayer == 'infrastructure') {
    return _isProtocolAdapter(target);
  }

  if (source.feature != null &&
      target.feature != null &&
      source.feature != target.feature) {
    return targetLayer == 'application' ||
        targetLayer == 'domain' ||
        (sourceLayer == 'infrastructure' &&
            target.feature == 'persistence' &&
            targetLayer == 'infrastructure');
  }
  if (source.module == 'features') {
    if (target.module != 'features') return target.module == 'core';
    if (sourceLayer == 'domain') {
      return targetLayer == 'domain' ||
          (targetLayer == 'application' &&
              (_isPort(target) || target.path.contains('/contracts/')));
    }
    if (sourceLayer == 'presentation') {
      return targetLayer == 'presentation' ||
          targetLayer == 'application' ||
          targetLayer == 'domain';
    }
    if (sourceLayer == 'application') {
      return targetLayer == 'application' || targetLayer == 'domain';
    }
    if (sourceLayer == 'runtime') {
      return targetLayer == 'runtime' ||
          targetLayer == 'application' ||
          targetLayer == 'domain';
    }
    if (sourceLayer == 'infrastructure') {
      return targetLayer == 'infrastructure' ||
          targetLayer == 'application' ||
          targetLayer == 'domain';
    }
  }
  return false;
}

void _expectEmpty(String label, List<String> violations) {
  expect(violations, isEmpty, reason: '$label\n${violations.join('\n')}');
}

Future<ResolvedUnitResult?> _resolveSource(_Source source) async {
  final path = File(source.path).absolute.path;
  final collection = AnalysisContextCollection(
    includedPaths: [path],
    sdkPath: _analysisSdkPath(),
  );
  try {
    final result = await collection
        .contextFor(path)
        .currentSession
        .getResolvedUnit(path);
    return result is ResolvedUnitResult ? result : null;
  } finally {
    await collection.dispose();
  }
}

void main() {
  late _Graph graph;

  setUpAll(() async {
    graph = await _readGraph();
  });

  test('every production file belongs to a declared module', () {
    final violations = <String>[];
    for (final source in graph.sources) {
      if (!_modules.contains(source.module)) {
        violations.add('${source.path}: undeclared module');
      }
      if (source.module == 'features' && source.layer == null) {
        final segments = source.path.substring('lib/'.length).split('/');
        if (!(segments.length == 3 && segments.last.endsWith('_port.dart'))) {
          violations.add('${source.path}: feature file has no declared layer');
        }
      }
    }
    _expectEmpty('module inventory', violations);
  });

  test('all internal imports and parts resolve', () {
    final violations = <String>[];
    for (final source in graph.sources) {
      for (final directive in [
        ...source.imports,
        ...source.exports,
        ...source.parts,
      ]) {
        final target = _resolve(source.path, directive.uri);
        if (target.isNotEmpty && !graph.byPath.containsKey(target)) {
          violations.add('${source.path}:${directive.line}: missing $target');
        }
      }
    }
    _expectEmpty('internal references', violations);
  });

  test('dependency direction is explicit and the graph is acyclic', () {
    final violations = <String>[];
    for (final source in graph.sources) {
      for (final directive in [...source.imports, ...source.exports]) {
        final target = graph.byPath[_resolve(source.path, directive.uri)];
        if (target != null && !_allowed(source, target)) {
          violations.add(
            '${source.path}:${directive.line}: ${target.path} '
            '(imports and exports are architectural edges)',
          );
        }
      }
    }
    violations.addAll(_cycles(_importGraph(graph)));
    _expectEmpty('dependency graph', violations);
  });

  test('strict layer matrix rejects prohibited boundary edges', () {
    _Source source(String path) =>
        _Source(path, '', const [], const [], const []);

    expect(
      _allowed(
        source('lib/features/chat/presentation/chat.dart'),
        source('lib/features/chat/runtime/chat_session_runtime.dart'),
      ),
      isFalse,
    );
    expect(
      _allowed(
        source('lib/features/task/application/task_service.dart'),
        source('lib/features/task/infrastructure/task_repository.dart'),
      ),
      isFalse,
    );
    expect(
      _allowed(
        source('lib/features/task/domain/task_policy.dart'),
        source('lib/features/task/presentation/task_panel.dart'),
      ),
      isFalse,
    );
    expect(
      _allowed(
        source('lib/features/chat/runtime/chat_runtime.dart'),
        source(
          'lib/features/chat/infrastructure/chat_panel_protocol_adapter.dart',
        ),
      ),
      isTrue,
    );
  });

  test('core and contract modules stay platform independent', () {
    final violations = <String>[];
    for (final source in graph.sources) {
      if (source.module == 'core' || source.layer == 'domain') {
        if (RegExp(
          r'''import ['"](?:dart:io|package:flutter|package:http|package:sqflite|package:shared_preferences|package:path_provider|package:yaml|package:process)''',
        ).hasMatch(source.text)) {
          violations.add('${source.path}: platform dependency in core/domain');
        }
        if (source.layer == 'domain' &&
            RegExp(
              r'dart_mappable|core/serialization/json_hooks|features/persistence/infrastructure|\.mapper\.dart',
            ).hasMatch(source.text)) {
          violations.add(
            '${source.path}: domain model owns persistence mapping concerns',
          );
        }
      }
    }
    _expectEmpty('platform-independent contracts', violations);
  });

  test('platform adapters do not leak through core or contract modules', () {
    final violations = <String>[];
    for (final source in graph.sources) {
      if (source.module == 'core' &&
          RegExp(
            r'''import ['"](?:dart:io|package:flutter|package:http|package:sqflite|package:shared_preferences|package:path_provider|package:yaml|package:process)''',
          ).hasMatch(source.text)) {
        violations.add('${source.path}: concrete platform import in core');
      }
      if (source.path.contains('/application/contracts/') &&
          RegExp(
            r'''import ['"](?:dart:io|package:flutter|package:http|package:sqflite|package:shared_preferences|package:path_provider|package:yaml|package:process)''',
          ).hasMatch(source.text)) {
        violations.add(
          '${source.path}: concrete platform import in application contract',
        );
      }
    }
    _expectEmpty('contract platform isolation', violations);
  });

  test('shared model/workflow contracts have neutral ownership', () {
    final violations = <String>[];
    final neutral = graph.byPath['lib/core/contracts/model_conversation.dart'];
    final store = graph.byPath['lib/core/contracts/conversation_store.dart'];
    if (neutral == null) {
      violations.add('core/contracts/model_conversation.dart: missing');
    } else {
      for (final symbol in [
        'class ChatMessage',
        'enum MessageRole',
        'class ChatToken',
        'class ToolCallDelta',
        'class CompactionSettings',
      ]) {
        if (!neutral.text.contains(symbol)) {
          violations.add('model_conversation.dart: missing $symbol');
        }
      }
    }
    if (store == null) {
      violations.add('core/contracts/conversation_store.dart: missing');
    }
    final oldSharedContract = RegExp(
      r'features/chat/application/contracts/(?:chat_message|chat_token|message_role|compaction_settings|bubble|message_store_port)\.dart',
    );
    for (final source in graph.sources) {
      if (source.feature == 'chat') continue;
      if (oldSharedContract.hasMatch(source.text)) {
        violations.add(
          '${source.path}: imports a chat-owned shared model/workflow contract',
        );
      }
    }
    _expectEmpty('neutral contract ownership', violations);
  });

  test('domain state and persistence mapping have explicit homes', () {
    final violations = <String>[];
    for (final path in [
      'lib/features/task/domain/task.dart',
      'lib/features/project/domain/project.dart',
    ]) {
      final source = graph.byPath[path];
      if (source == null) {
        violations.add('$path: domain state surface is missing');
        continue;
      }
      if (RegExp(
        r'dart_mappable|core/serialization/json_hooks|features/persistence/infrastructure|\.mapper\.dart',
      ).hasMatch(source.text)) {
        violations.add('$path: domain surface owns persistence concerns');
      }
    }
    final taskLifecycle =
        graph.byPath['lib/features/task/domain/task_lifecycle_service.dart'];
    final projectControl = graph
        .byPath['lib/features/project/domain/project_control_state_service.dart'];
    if (taskLifecycle == null ||
        !taskLifecycle.text.contains('features/task/domain/task.dart')) {
      violations.add('task lifecycle policy is not domain-owned');
    }
    if (projectControl == null ||
        !projectControl.text.contains('features/project/domain/project.dart')) {
      violations.add('project control policy is not domain-owned');
    }
    for (final path in [
      'lib/features/persistence/infrastructure/dto/project_snapshot_dto.dart',
      'lib/features/persistence/infrastructure/dto/task_snapshot_dto.dart',
      'lib/features/persistence/infrastructure/dto/project_persistence_adapter.dart',
      'lib/features/persistence/infrastructure/dto/task_persistence_adapter.dart',
    ]) {
      final source = graph.byPath[path];
      if (source == null) {
        violations.add('$path: explicit persistence mapper is missing');
      }
    }
    _expectEmpty('domain/persistence ownership', violations);
  });

  test('durable aggregates are defined in domain rather than re-exported', () {
    final violations = <String>[];
    const domainSurfaces = <String, String>{
      'lib/features/project/domain/project.dart': 'ProjectAggregate',
      'lib/features/task/domain/task.dart': 'class TaskAggregate',
    };
    for (final entry in domainSurfaces.entries) {
      final source = graph.byPath[entry.key];
      if (source == null) {
        violations.add('${entry.key}: domain surface is missing');
        continue;
      }
      if (!source.text.contains(entry.value)) {
        violations.add(
          '${entry.key}: ${entry.value} is still owned by another layer',
        );
      }
      if (RegExp(
        r'features/(?:project|task)/application/contracts/.*snapshot_models',
      ).hasMatch(source.text)) {
        violations.add('${entry.key}: re-exports application snapshot models');
      }
      if (RegExp(
        r'dart_mappable|core/serialization/json_hooks|\.mapper\.dart',
      ).hasMatch(source.text)) {
        violations.add('${entry.key}: domain surface depends on mapping code');
      }
    }
    for (final source in graph.sources.where(
      (source) =>
          source.path.contains('/features/project/domain/') ||
          source.path.contains('/features/task/domain/'),
    )) {
      if (RegExp(
        r'''import ['"](?:dart:convert|package:dart_mappable)|core/model_json|features/persistence|application/contracts/.*snapshot_models''',
      ).hasMatch(source.text)) {
        violations.add(
          '${source.path}: domain imports persistence/wire concerns',
        );
      }
    }
    _expectEmpty('durable aggregate ownership', violations);
  });

  test('durable aggregate mappers live at the persistence boundary', () {
    final violations = <String>[];
    for (final path in [
      'lib/features/project/application/contracts/project_snapshot_models.dart',
      'lib/features/task/application/contracts/task_snapshot_models.dart',
    ]) {
      final source = graph.byPath[path];
      if (source == null) continue;
      if (source.text.contains('dart_mappable') ||
          source.text.contains('.mapper.dart')) {
        violations.add(
          '$path: durable aggregate mapper remains in application',
        );
      }
    }
    for (final source in graph.sources.where(
      (source) => source.path.endsWith('.mapper.dart'),
    )) {
      if (source.path.contains('project_state_models') ||
          source.path.contains('task_state_models')) {
        if (!source.path.contains('/features/persistence/infrastructure/')) {
          violations.add(
            '${source.path}: durable aggregate mapper is outside persistence',
          );
        }
      }
    }
    final codec = graph
        .byPath['lib/features/persistence/infrastructure/dto/aggregate_snapshot_codecs.dart'];
    if (codec == null ||
        !codec.text.contains('class ProjectSnapshotCodec') ||
        !codec.text.contains('class TaskSnapshotCodec') ||
        !codec.text.contains('ModelJson.register')) {
      violations.add(
        'aggregate_snapshot_codecs.dart: explicit aggregate mapping is missing',
      );
    }
    _expectEmpty('durable mapper placement', violations);
  });

  test('application persistence ports do not expose adapter layout seams', () {
    final violations = <String>[];
    final projectPort =
        graph.byPath['lib/features/project/project_repository_port.dart'];
    final taskPort = graph
        .byPath['lib/features/task/application/task_application/task_persistence_ports.dart'];
    if (projectPort == null ||
        RegExp(
          r'projectRelativePath|projectSnapshotPath|projectsRoot|documentFileName',
        ).hasMatch(projectPort.text)) {
      violations.add('project_repository_port.dart: filesystem layout leaked');
    }
    if (taskPort == null ||
        RegExp(
          r'coordinator|taskRelativePath|TaskStorageLayout',
        ).hasMatch(taskPort.text)) {
      violations.add('task_persistence_ports.dart: adapter seam leaked');
    }
    for (final path in [
      'lib/features/persistence/application/project_snapshot_store_port.dart',
      'lib/features/persistence/application/task_snapshot_store_port.dart',
    ]) {
      final source = graph.byPath[path];
      if (source == null ||
          !source.text.contains('SnapshotStorePort') ||
          !source.text.contains('RelativePath')) {
        violations.add('$path: infrastructure storage capability is missing');
      }
    }
    _expectEmpty('persistence port seams', violations);
  });

  test('application and runtime orchestration use typed platform ports', () {
    final violations = <String>[];
    for (final source in graph.sources) {
      if (source.module != 'features' ||
          (source.layer != 'application' && source.layer != 'runtime')) {
        continue;
      }
      if (RegExp(
        r'''import ['"](?:dart:io|package:http|package:sqflite|package:shared_preferences|package:path_provider|package:yaml|package:process)''',
      ).hasMatch(source.text)) {
        violations.add('${source.path}: concrete platform import');
      }
    }
    _expectEmpty('application/runtime platform isolation', violations);
  });

  test('application/runtime ports have no raw transport seams', () {
    final violations = <String>[];
    for (final source in graph.sources.where(_isPort)) {
      if (!source.path.contains('/application/')) continue;
      if (RegExp(
        r'^\s*(?:Future|Stream|List|Map|String|void|[A-Z]\w*)[^;{}\n]*(?:Map<String,\s*dynamic>|Process|StreamSubscription|ValueNotifier|LlamaServerHandle|String\s+\w*(?:Json|JSON|json))',
        multiLine: true,
      ).hasMatch(source.text)) {
        violations.add('${source.path}: raw/infrastructure boundary type');
      }
    }
    for (final source in graph.sources.where(
      (source) =>
          source.layer == 'application' &&
          source.text.contains('abstract interface class') &&
          !source.path.contains('/protocol/'),
    )) {
      for (final body in _interfaceBodies(source.text)) {
        if (RegExp(
          r'Map<String,\s*dynamic>|Process|StreamSubscription|ValueNotifier|LlamaServerHandle|String\s+\w*(?:Json|JSON|json)',
        ).hasMatch(body)) {
          violations.add('${source.path}: raw/infrastructure port seam');
        }
      }
    }
    _expectEmpty('typed ports', violations);
  });

  test('framework notifier coupling is explicit and documented', () {
    const justified = <String, String>{
      'lib/features/chat/application/chat_library_service.dart':
          'ChatLibraryService',
      'lib/features/chat/application/system_prompt_library_service.dart':
          'SystemPromptLibraryService',
      'lib/features/model/application/model_server_port.dart':
          'ModelServerPort',
      'lib/features/model/application/model_session_diagnostics.dart':
          'ModelSessionDiagnostics',
    };
    final violations = <String>[];
    for (final source in graph.sources.where(
      (source) => source.layer == 'application',
    )) {
      if (!RegExp(
        r'ChangeNotifier|ValueNotifier|ValueListenable',
      ).hasMatch(source.text)) {
        continue;
      }
      if (!justified.containsKey(source.path)) {
        violations.add('${source.path}: undocumented framework notifier edge');
      }
    }
    _expectEmpty('framework notifier coupling', violations);
  });

  test('workspace discovery is an injected application capability', () {
    final port = graph
        .byPath['lib/features/workspace/application/workspace_discovery.dart'];
    final adapter = graph
        .byPath['lib/features/workspace/infrastructure/workspace_discovery_service.dart'];
    final composition =
        graph.byPath['lib/app/modules/workspace_tools_module.dart'];
    final violations = <String>[];
    if (port == null || !port.text.contains('WorkspaceDiscoveryPort')) {
      violations.add('workspace_discovery.dart: application port is missing');
    }
    if (adapter == null ||
        !adapter.text.contains('implements WorkspaceDiscoveryPort')) {
      violations.add(
        'workspace_discovery_service.dart: infrastructure adapter is not '
        'bound to the application port',
      );
    }
    if (composition == null ||
        !composition.text.contains('WorkspaceDiscoveryPort') ||
        !composition.text.contains('discovery:')) {
      violations.add(
        'workspace_tools_module.dart: discovery adapter is not composed '
        'and exposed as a typed port',
      );
    }
    for (final source in graph.sources) {
      if (!source.path.contains('/runtime/') &&
          !source.path.contains('/application/')) {
        continue;
      }
      if (source.text.contains(
        'features/workspace/infrastructure/workspace_discovery_service.dart',
      )) {
        violations.add('${source.path}: imports concrete workspace discovery');
      }
    }
    _expectEmpty('workspace discovery boundary', violations);
  });

  test('model and diagnostics boundaries are hardened', () {
    final model =
        graph.byPath['lib/features/model/application/model_server_port.dart']!;
    final diagnostics = graph
        .byPath['lib/features/model/application/model_session_diagnostics_port.dart']!;
    final sessionManager = graph
        .byPath['lib/features/chat/runtime/chat_application/chat_session_manager.dart'];
    final violations = <String>[];
    if (RegExp(
      r'Process|StreamSubscription|LlamaServerHandle|ValueNotifier|set[A-Z]|ModelProvider|ModelCompletionPort',
    ).hasMatch(model.text)) {
      violations.add(
        'model_server_port.dart exposes infrastructure or setters',
      );
    }
    final telemetry = graph
        .byPath['lib/features/model/application/model_session_telemetry_port.dart'];
    if (telemetry == null ||
        !telemetry.text.contains('ModelSessionTelemetryPort')) {
      violations.add('diagnostics read/write contracts are not separated');
    }
    if (RegExp(
      r'\b(?:record|update|clear|set)[A-Z]',
    ).hasMatch(diagnostics.text)) {
      violations.add('diagnostics read port exposes telemetry mutation');
    }
    if (sessionManager != null &&
        sessionManager.text.contains('ModelServerPort')) {
      violations.add(
        'chat_session_manager.dart: broad server lifecycle port leaked into session work',
      );
    }
    final requestOptions =
        graph.byPath['lib/features/model/application/model_request.dart']!;
    if (RegExp(
      r'fromWire|toWire|Map<String,\s*Object',
    ).hasMatch(requestOptions.text)) {
      violations.add('model request options expose transport maps');
    }
    _expectEmpty('model boundary', violations);
  });

  test('model server lifecycle and active-session capabilities are split', () {
    final server =
        graph.byPath['lib/features/model/application/model_server_port.dart'];
    final context =
        graph.byPath['lib/features/chat/runtime/chat_use_case_context.dart'];
    final violations = <String>[];
    if (server == null) {
      violations.add('model_server_port.dart: focused server port is missing');
    } else {
      for (final required in [
        'ModelServerLifecyclePort',
        'ActiveModelSessionPort',
        'ModelServerPort',
      ]) {
        if (!server.text.contains('class $required')) {
          violations.add('model_server_port.dart: missing $required');
        }
      }
    }
    if (context == null) {
      violations.add('chat_use_case_context.dart: context is missing');
    } else if (context.text.contains('ModelServerPort get serverManager')) {
      violations.add(
        'chat_use_case_context.dart: use cases depend on the combined server port',
      );
    }
    _expectEmpty('focused model server capabilities', violations);
  });

  test('runtime collaborator files contain wiring only', () {
    final violations = <String>[];
    for (final source in graph.sources.where(
      (source) => source.path.endsWith('_runtime_collaborators.dart'),
    )) {
      if (RegExp(
        r'\bextension\s+|\bclass\s+\w+\s+extends|\bFuture<',
      ).hasMatch(source.text)) {
        violations.add(
          '${source.path}: orchestration implementation in wiring file',
        );
      }
    }
    _expectEmpty('runtime wiring files', violations);
  });

  test('runtime orchestration is class-based and responsibility-focused', () {
    final violations = <String>[];
    for (final source in graph.sources.where(
      (source) => source.path.endsWith('_runtime_orchestrator.dart'),
    )) {
      if (RegExp(r'^extension\s+', multiLine: true).hasMatch(source.text)) {
        violations.add('${source.path}: extension-based orchestration remains');
      }
      if (RegExp(r'RuntimeContext').hasMatch(source.text)) {
        violations.add('${source.path}: mutable runtime context remains');
      }
    }
    const requiredTypes = <String, List<String>>{
      'lib/features/task/runtime/task_step_execution_runtime.dart': [
        'class TaskStepExecutionRuntime',
      ],
      'lib/features/task/runtime/task_execution_coordinator.dart': [
        'class TaskExecutionCoordinator',
      ],
      'lib/features/task/runtime/task_execution_policy.dart': [
        'class TaskExecutionPolicy',
      ],
      'lib/features/task/runtime/task_step_execution_loop.dart': [
        'class TaskStepExecutionLoop',
      ],
      'lib/features/task/runtime/task_planning_coordinator.dart': [
        'class TaskPlanningCoordinator',
      ],
      'lib/features/task/runtime/task_gate_evaluator.dart': [
        'class TaskGateEvaluator',
      ],
      'lib/features/task/runtime/task_command_service.dart': [
        'class TaskCommandService',
      ],
      'lib/features/task/runtime/task_step_runner.dart': [
        'class TaskStepRunner',
      ],
      'lib/features/task/runtime/task_recovery_service.dart': [
        'class TaskRecoveryService',
      ],
      'lib/features/task/runtime/task_persistence_store.dart': [
        'class TaskPersistenceStore',
      ],
      'lib/features/task/runtime/task_command_use_case.dart': [
        'class TaskCommandUseCase',
      ],
      'lib/features/task/runtime/task_planning_use_case.dart': [
        'class TaskPlanningUseCase',
      ],
      'lib/features/task/runtime/task_persistence_use_case.dart': [
        'class TaskPersistenceUseCase',
      ],
      'lib/features/task/runtime/task_execution_use_case.dart': [
        'class TaskExecutionUseCase',
      ],
      'lib/features/project/runtime/project_command_service.dart': [
        'class ProjectCommandService',
      ],
      'lib/features/project/runtime/project_handlers.dart': [
        'class ProjectPlanningHandler',
        'class ProjectPersistenceHandler',
        'class ProjectRecoveryHandler',
      ],
      'lib/features/chat/runtime/chat_application/chat_session_manager.dart': [
        'class ChatSessionManager',
      ],
      'lib/features/chat/runtime/chat_application/chat_command_coordinator.dart':
          ['class ChatCommandCoordinator'],
      'lib/features/chat/runtime/chat_application/chat_tool_execution_service.dart':
          ['class ChatToolExecutionService'],
      'lib/features/chat/runtime/chat_application/chat_persistence_runtime.dart':
          ['class ChatPersistenceRuntime'],
      'lib/features/chat/runtime/chat_application/chat_prompt_construction_service.dart':
          ['class ChatPromptConstructionService'],
      'lib/features/project/runtime/project_persistence_runtime.dart': [
        'class ProjectPersistenceRuntime',
      ],
      'lib/features/project/runtime/project_execution_runtime.dart': [
        'typedef ProjectExecutionRuntime',
      ],
      'lib/features/project/runtime/project_execution_state_machine.dart': [
        'class ProjectExecutionStateMachine',
      ],
      'lib/features/project/runtime/project_persistence_coordinator.dart': [
        'class ProjectPersistenceCoordinator',
      ],
      'lib/features/project/runtime/project_plan_revision_coordinator.dart': [
        'class ProjectPlanRevisionCoordinator',
      ],
      'lib/features/project/runtime/project_evaluation_coordinator.dart': [
        'class ProjectEvaluationCoordinator',
      ],
      'lib/features/project/runtime/project_planning_use_case.dart': [
        'class ProjectPlanningUseCase',
      ],
      'lib/features/project/runtime/project_user_command_coordinator.dart': [
        'class ProjectUserCommandCoordinator',
      ],
      'lib/features/project/runtime/project_recovery_policy.dart': [
        'class ProjectRecoveryPolicy',
      ],
      'lib/features/project/runtime/project_recovery_service.dart': [
        'class ProjectRecoveryService',
      ],
      'lib/features/project/runtime/project_evidence_service.dart': [
        'class ProjectEvidenceService',
      ],
      'lib/features/project/runtime/project_completion_service.dart': [
        'class ProjectCompletionService',
      ],
      'lib/features/chat/runtime/chat_session_runtime.dart': [
        'typedef ChatSessionRuntime',
      ],
      'lib/features/chat/runtime/chat_session_orchestrator.dart': [
        'class ChatSessionOrchestrator',
      ],
      'lib/features/chat/runtime/chat_presentation_message_builder.dart': [
        'class ChatPresentationMessageBuilder',
      ],
      'lib/features/chat/runtime/chat_autosave_coordinator.dart': [
        'class ChatAutosaveCoordinator',
      ],
      'lib/features/chat/runtime/chat_workspace_lifecycle_coordinator.dart': [
        'class ChatWorkspaceLifecycleCoordinator',
      ],
      'lib/features/chat/runtime/chat_command_dispatcher.dart': [
        'class ChatCommandDispatcher',
      ],
      'lib/features/chat/runtime/chat_task_command_coordinator.dart': [
        'class ChatTaskCommandCoordinator',
      ],
      'lib/features/chat/runtime/chat_project_command_coordinator.dart': [
        'class ChatProjectCommandCoordinator',
      ],
      'lib/features/chat/runtime/chat_session_lifecycle_use_case.dart': [
        'class ChatSessionLifecycleUseCase',
      ],
      'lib/features/chat/runtime/chat_state_mutation_use_case.dart': [
        'class ChatStateMutationUseCase',
      ],
      'lib/features/chat/runtime/chat_work_use_case.dart': [
        'class ChatWorkUseCase',
      ],
      'lib/features/chat/runtime/chat_task_plan_use_case.dart': [
        'class ChatTaskPlanUseCase',
      ],
      'lib/features/chat/runtime/chat_task_replan_use_case.dart': [
        'class ChatTaskReplanUseCase',
      ],
      'lib/features/chat/runtime/chat_exit_use_case.dart': [
        'class ChatExitUseCase',
      ],
      'lib/features/model/infrastructure/chat_sse_parser.dart': [
        'class ChatSseParser',
      ],
    };
    for (final entry in requiredTypes.entries) {
      final source = graph.byPath[entry.key];
      if (source == null) {
        violations.add('${entry.key}: focused runtime service is missing');
        continue;
      }
      for (final type in entry.value) {
        if (!source.text.contains(type)) {
          violations.add('${entry.key}: missing $type');
        }
      }
    }
    const facades = <String>{
      'lib/features/project/runtime/project_execution_runtime.dart',
      'lib/features/task/runtime/task_step_execution_runtime.dart',
      'lib/features/chat/runtime/chat_session_runtime.dart',
    };
    for (final path in facades) {
      final source = graph.byPath[path];
      if (source == null) continue;
      if (source.text.split('\n').length > 80) {
        violations.add('$path: compatibility facade is not thin');
      }
      if (RegExp(r'^\s*Future<', multiLine: true).hasMatch(source.text)) {
        violations.add('$path: facade contains runtime implementation methods');
      }
    }
    const collaboratorEdges = <String, List<String>>{
      'lib/features/project/runtime/project_execution_state_machine.dart': [
        '_persistenceCoordinator',
        '_planRevisionCoordinator',
        '_evaluationCoordinator',
        '_planningUseCase',
        '_userCommands',
      ],
      'lib/features/task/runtime/task_execution_coordinator.dart': [
        '_stepLoop',
        '_executionPolicy',
        '_commandUseCase',
        '_planningUseCase',
        '_persistenceUseCase',
        '_executionUseCase',
      ],
      'lib/features/chat/runtime/chat_session_orchestrator.dart': [
        '_presentationMessages',
        '_autosave',
        '_workspaceLifecycle',
        '_commandDispatcher',
        '_taskCommandCoordinator',
        '_projectCommandCoordinator',
        '_taskPlanUseCase',
        '_taskReplanUseCase',
        '_exitUseCase',
        '_sessionLifecycleUseCase',
        '_workUseCase',
        '_stateMutationUseCase',
      ],
    };
    for (final entry in collaboratorEdges.entries) {
      final source = graph.byPath[entry.key];
      if (source == null) continue;
      for (final field in entry.value) {
        if (!source.text.contains(field)) {
          violations.add('${entry.key}: missing collaborator field $field');
        }
      }
    }
    _expectEmpty('runtime orchestration decomposition', violations);
  });

  test('use-case services do not depend on concrete runtime facades', () {
    const useCasePaths = <String>{
      'lib/features/project/runtime/project_planning_use_case.dart',
      'lib/features/project/runtime/project_user_command_coordinator.dart',
      'lib/features/task/runtime/task_planning_use_case.dart',
      'lib/features/task/runtime/task_execution_use_case.dart',
      'lib/features/task/runtime/task_command_use_case.dart',
      'lib/features/task/runtime/task_persistence_use_case.dart',
      'lib/features/chat/runtime/chat_session_lifecycle_use_case.dart',
      'lib/features/chat/runtime/chat_work_use_case.dart',
      'lib/features/chat/runtime/chat_state_mutation_use_case.dart',
      'lib/features/chat/runtime/chat_task_plan_use_case.dart',
      'lib/features/chat/runtime/chat_task_replan_use_case.dart',
      'lib/features/chat/runtime/chat_exit_use_case.dart',
    };
    const forbiddenConcreteHosts = <String>{
      'ProjectExecutionStateMachine',
      'TaskExecutionCoordinator',
      'ChatSessionOrchestrator',
    };
    const requiredContexts = <String, String>{
      'lib/features/project/runtime/project_planning_use_case.dart':
          'ProjectPlanningCapabilities',
      'lib/features/project/runtime/project_user_command_coordinator.dart':
          'ProjectCommandCapabilities',
      'lib/features/task/runtime/task_planning_use_case.dart':
          'TaskPlanningCapabilities',
      'lib/features/task/runtime/task_execution_use_case.dart':
          'TaskExecutionCapabilities',
      'lib/features/task/runtime/task_command_use_case.dart':
          'TaskCommandCapabilities',
      'lib/features/task/runtime/task_persistence_use_case.dart':
          'TaskPersistenceCapabilities',
      'lib/features/chat/runtime/chat_session_lifecycle_use_case.dart':
          'ChatSessionLifecycleCapabilities',
      'lib/features/chat/runtime/chat_work_use_case.dart':
          'ChatWorkCapabilities',
      'lib/features/chat/runtime/chat_state_mutation_use_case.dart':
          'ChatStateMutationCapabilities',
      'lib/features/chat/runtime/chat_task_plan_use_case.dart':
          'ChatTaskPlanCapabilities',
      'lib/features/chat/runtime/chat_task_replan_use_case.dart':
          'ChatTaskReplanCapabilities',
      'lib/features/chat/runtime/chat_exit_use_case.dart':
          'ChatExitCapabilities',
    };
    final violations = <String>[];
    for (final path in useCasePaths) {
      final source = graph.byPath[path];
      if (source == null) {
        violations.add('$path: use-case source is missing');
        continue;
      }
      for (final host in forbiddenConcreteHosts) {
        if (RegExp('\\b$host\\b').hasMatch(source.text)) {
          violations.add(
            '$path: concrete runtime host $host leaked into use case',
          );
        }
      }
      final context = requiredContexts[path]!;
      if (!source.text.contains(context)) {
        violations.add('$path: missing focused $context dependency');
      }
      if (RegExp(r'\b(?:UseCase|Coordinator)\(this\)').hasMatch(source.text)) {
        violations.add('$path: use case is constructed from a concrete host');
      }
      if (source.text.contains('ChatUseCaseContext')) {
        violations.add('$path: broad ChatUseCaseContext leaked into use case');
      }
    }
    for (final path in <String>[
      'lib/features/project/runtime/project_execution_state_machine.dart',
      'lib/features/task/runtime/task_execution_coordinator.dart',
      'lib/features/chat/runtime/chat_session_orchestrator.dart',
    ]) {
      final source = graph.byPath[path];
      if (source == null) continue;
      if (RegExp(r'\b(?:UseCase|Coordinator)\(this\)').hasMatch(source.text)) {
        violations.add(
          '$path: facade directly constructs a host-coupled use case',
        );
      }
    }
    _expectEmpty('use-case context boundaries', violations);
  });

  test('workflow operation parts target use-case boundaries', () {
    const requiredTargets = <String, String>{
      'lib/features/project/runtime/project_execution_core.dart':
          'extension ProjectExecutionCore on ProjectExecutionUseCase',
      'lib/features/project/runtime/project_execution_operations.dart':
          'extension ProjectExecutionOperations on ProjectExecutionUseCase',
      'lib/features/project/runtime/project_execution_lifecycle.dart':
          'extension ProjectExecutionLifecycle on ProjectExecutionUseCase',
      'lib/features/task/runtime/task_execution_planning.dart':
          'extension TaskExecutionPlanning on TaskPlanningUseCase',
      'lib/features/task/runtime/task_execution_operations.dart':
          'extension TaskExecutionOperations on TaskExecutionUseCase',
      'lib/features/chat/runtime/chat_session_commands.dart':
          'extension ChatSessionCommands on ChatWorkUseCase',
      'lib/features/chat/runtime/chat_session_operations.dart':
          'extension ChatSessionOperations on ChatWorkUseCase',
    };
    final violations = <String>[];
    for (final entry in requiredTargets.entries) {
      final source = graph.byPath[entry.key];
      if (source == null) {
        violations.add('${entry.key}: workflow part is missing');
      } else if (!source.text.contains(entry.value)) {
        violations.add('${entry.key}: workflow part targets a facade');
      }
    }
    const forbiddenFacadeTargets = <String>{
      'ProjectExecutionStateMachine',
      'TaskExecutionCoordinator',
      'ChatSessionOrchestrator',
    };
    for (final entry in requiredTargets.entries) {
      final source = graph.byPath[entry.key];
      if (source == null) continue;
      for (final facade in forbiddenFacadeTargets) {
        if (RegExp('extension [^\\n]+ on $facade').hasMatch(source.text)) {
          violations.add('${entry.key}: concrete facade target $facade');
        }
      }
    }
    _expectEmpty('workflow use-case targets', violations);
  });

  test('orchestration budgets and focused capability seams are enforced', () {
    const budgets = <String, int>{
      'lib/features/project/runtime/project_execution_state_machine.dart': 700,
      'lib/features/task/runtime/task_execution_coordinator.dart': 700,
      'lib/features/chat/runtime/chat_session_orchestrator.dart': 800,
    };
    final violations = <String>[];
    for (final entry in budgets.entries) {
      final source = graph.byPath[entry.key];
      if (source == null) {
        violations.add('${entry.key}: orchestration facade is missing');
        continue;
      }
      final lineCount = source.text.split('\n').length;
      if (lineCount > entry.value) {
        violations.add(
          '${entry.key}: $lineCount lines exceeds facade budget ${entry.value}',
        );
      }
    }

    final constructorBudgets = <String, int>{
      'lib/features/project/runtime/project_execution_state_machine.dart': 20,
      'lib/features/chat/runtime/chat_session_orchestrator.dart': 24,
    };
    for (final entry in constructorBudgets.entries) {
      final source = graph.byPath[entry.key]!;
      final className = entry.key.contains('project_execution')
          ? 'ProjectExecutionStateMachine'
          : 'ChatSessionOrchestrator';
      final classOffset = source.text.indexOf('class $className');
      final constructorOffset = source.text.indexOf('$className(', classOffset);
      final constructorEnd = source.text.indexOf('})', constructorOffset);
      if (classOffset < 0 || constructorOffset < 0 || constructorEnd < 0) {
        violations.add('${entry.key}: constructor cannot be measured');
        continue;
      }
      final constructor = source.text.substring(
        constructorOffset,
        constructorEnd,
      );
      final requiredCount = RegExp(
        r'\brequired\b',
      ).allMatches(constructor).length;
      if (requiredCount > entry.value) {
        violations.add(
          '${entry.key}: constructor has $requiredCount required inputs; '
          'budget is ${entry.value}',
        );
      }
    }

    final modelCapabilities =
        graph.byPath['lib/features/model/application/model_capabilities.dart'];
    if (modelCapabilities == null) {
      violations.add(
        'model_capabilities.dart: focused model ports are missing',
      );
    } else {
      for (final name in [
        'ModelTextCompletionPort',
        'ModelStreamingPort',
        'ModelTokenCountingPort',
        'ModelMetadataPort',
        'ModelLifecyclePort',
        'ModelGenerationPort',
        'ModelContextPort',
        'ModelConversationPort',
      ]) {
        if (!modelCapabilities.text.contains('class $name')) {
          violations.add('model_capabilities.dart: missing $name');
        }
      }
    }
    const focusedWorkspaceConsumers = <String>{
      'lib/features/task/runtime/task_execution_coordinator.dart',
      'lib/features/task/runtime/task_tool_execution_service.dart',
      'lib/features/task/runtime/task_gate_evaluator.dart',
      'lib/features/project/runtime/project_planning_workspace_reader.dart',
    };
    for (final path in focusedWorkspaceConsumers) {
      final source = graph.byPath[path];
      if (source != null && source.text.contains('WorkspaceSandboxPort')) {
        violations.add(
          '$path: broad WorkspaceSandboxPort leaked into feature runtime',
        );
      }
    }
    const focusedPreferencesConsumers = <String>{
      'lib/features/chat/runtime/chat_session_orchestrator.dart',
      'lib/features/chat/runtime/chat_application/chat_session_manager.dart',
      'lib/features/chat/presentation/theme_manager.dart',
      'lib/features/chat/presentation/chat/model_picker.dart',
      'lib/features/chat/presentation/overlays/settings.dart',
      'lib/features/chat/presentation/chat/diagnostics_bar.dart',
    };
    for (final path in focusedPreferencesConsumers) {
      final source = graph.byPath[path];
      if (source != null &&
          RegExp(r'\bPreferencesPort\b').hasMatch(source.text)) {
        violations.add('$path: broad PreferencesPort leaked into feature code');
      }
    }
    final picker =
        graph.byPath['lib/features/chat/presentation/chat/model_picker.dart'];
    if (picker == null) {
      violations.add('model_picker.dart: presentation model picker is missing');
    } else {
      for (final forbidden in [
        'dart:io',
        'ModelsDirectory',
        'Platform.numberOfProcessors',
        'List<dynamic>',
      ]) {
        if (picker.text.contains(forbidden)) {
          violations.add('model_picker.dart: platform/untyped seam $forbidden');
        }
      }
      for (final required in ['ModelCatalogPort', 'ModelDescriptor']) {
        if (!picker.text.contains(required)) {
          violations.add(
            'model_picker.dart: missing typed catalog seam $required',
          );
        }
      }
    }
    for (final source in graph.sources.where(
      (source) => source.path.contains('/presentation/'),
    )) {
      if (RegExp(r'''import ['"]dart:io['"]''').hasMatch(source.text)) {
        violations.add('${source.path}: presentation imports dart:io');
      }
      if (source.text.contains('Platform.numberOfProcessors')) {
        violations.add(
          '${source.path}: presentation reads platform processor defaults',
        );
      }
    }
    for (final source in graph.sources.where(
      (source) => source.path.endsWith('.mapper.dart'),
    )) {
      if (source.layer == 'domain' || source.layer == 'runtime') {
        violations.add(
          '${source.path}: generated mapper is inside domain/runtime code',
        );
      }
    }
    _expectEmpty('architecture budgets and focused capabilities', violations);
  });

  test('orchestration operation parts stay responsibility-sized', () {
    const budgets = <String, int>{
      'lib/features/project/runtime/project_recovery_policy.dart': 650,
      'lib/features/project/runtime/project_execution_operations.dart': 1500,
      'lib/features/project/runtime/project_execution_core.dart': 1100,
      'lib/features/project/runtime/project_execution_lifecycle.dart': 1900,
      'lib/features/task/runtime/task_step_execution_loop.dart': 650,
      'lib/features/task/runtime/task_execution_operations.dart': 1000,
      'lib/features/task/runtime/task_execution_planning.dart': 1700,
      'lib/features/chat/runtime/chat_session_operations.dart': 1100,
      'lib/features/chat/runtime/chat_session_commands.dart': 750,
      'lib/features/chat/runtime/chat_session_state_operations.dart': 1000,
    };
    final violations = <String>[];
    for (final entry in budgets.entries) {
      final source = graph.byPath[entry.key];
      if (source == null) {
        violations.add('${entry.key}: orchestration part is missing');
        continue;
      }
      final lineCount = source.text.split('\n').length;
      if (lineCount > entry.value) {
        violations.add(
          '${entry.key}: $lineCount lines exceeds operation budget '
          '${entry.value}',
        );
      }
    }
    _expectEmpty('orchestration operation budgets', violations);
  });

  test('planning and panel responsibility budgets are explicit', () {
    const budgets = <String, int>{
      'lib/features/project/runtime/project_plan_builder.dart': 250,
      'lib/features/project/runtime/project_plan_builder_commands.dart': 900,
      'lib/features/project/runtime/project_plan_builder_support.dart': 800,
      'lib/features/project/runtime/project_plan_builder_workspace.dart': 400,
      'lib/features/project/runtime/project_planning_tools.dart': 750,
      'lib/features/project/runtime/project_planning_tool_command_service.dart':
          850,
      'lib/features/project/runtime/project_plan_editing_command_service.dart':
          650,
      'lib/features/project/runtime/project_planning_workspace_command_service.dart':
          400,
      'lib/features/task/runtime/task_gate_evaluator.dart': 850,
      'lib/features/task/runtime/task_gate_file_validation_service.dart': 500,
      'lib/features/chat/presentation/chat/task_panel.dart': 1000,
      'lib/features/chat/presentation/chat/task_panel_project_sections.dart':
          750,
    };
    final violations = <String>[];
    for (final entry in budgets.entries) {
      final source = graph.byPath[entry.key];
      if (source == null) {
        violations.add('${entry.key}: focused unit is missing');
        continue;
      }
      final lineCount = source.text.split('\n').length;
      if (lineCount > entry.value) {
        violations.add(
          '${entry.key}: $lineCount lines exceeds responsibility budget '
          '${entry.value}',
        );
      }
    }
    _expectEmpty('planning/panel responsibility budgets', violations);
  });

  test('presentation consumes projections instead of aggregates', () {
    final violations = <String>[];
    for (final source in graph.sources.where(
      (source) => source.path.contains('/presentation/'),
    )) {
      if (RegExp(
            r'features/(project|task)/domain/(project|task)\.dart',
          ).hasMatch(source.text) ||
          source.text.contains('SnapshotDto') ||
          source.text.contains('ProjectAggregate') ||
          RegExp(r'\bTaskAggregate\b').hasMatch(source.text)) {
        violations.add(
          '${source.path}: presentation imports/uses a domain aggregate',
        );
      }
    }
    _expectEmpty('presentation projections', violations);
  });

  test('presentation wiring uses library application ports', () {
    final violations = <String>[];
    for (final source in graph.sources) {
      final isPresentation = source.path.contains('/presentation/');
      final isRoot = source.path == 'lib/main.dart';
      if (!isPresentation && !isRoot) continue;
      if (source.imports.any(
        (directive) =>
            directive.uri.endsWith('chat_library_service.dart') ||
            directive.uri.endsWith('system_prompt_library_service.dart'),
      )) {
        violations.add('${source.path}: concrete library service leaked');
      }
      if (source.text.contains('ChatLibraryService') ||
          source.text.contains('SystemPromptLibraryService')) {
        violations.add('${source.path}: concrete library service type leaked');
      }
    }
    _expectEmpty('presentation service boundary', violations);
  });

  test('presentation wiring uses chat capability ports', () {
    final violations = <String>[];
    for (final source in graph.sources) {
      if (!source.path.contains('/presentation/')) continue;
      if (source.imports.any(
        (directive) =>
            directive.uri.endsWith('chat_controller.dart') ||
            directive.uri.endsWith('chat_workspace_controller.dart'),
      )) {
        violations.add('${source.path}: concrete chat controller leaked');
      }
    }
    final ports = graph
        .byPath['lib/features/chat/application/contracts/chat_presentation_ports.dart'];
    if (ports == null ||
        !ports.text.contains('ChatTabPresentationPort') ||
        !ports.text.contains('ChatWorkspacePresentationPort')) {
      violations.add(
        'chat_presentation_ports.dart: focused chat ports missing',
      );
    }
    _expectEmpty('presentation chat capability boundary', violations);
  });

  test('chat panel read models do not retain domain aggregates', () {
    final readModels =
        graph.byPath['lib/features/chat/domain/chat_panel_read_models.dart'];
    final projection = graph
        .byPath['lib/features/chat/application/chat_panel_projection.dart'];
    final violations = <String>[];
    if (readModels == null) {
      violations.add(
        'chat_panel_read_models.dart: read-model module is missing',
      );
    } else {
      if (RegExp(
        r'features/(project|task)/domain/',
      ).hasMatch(readModels.text)) {
        violations.add(
          'chat_panel_read_models.dart: imports a project/task domain module',
        );
      }
      if (RegExp(
        r'\b(?:ProjectAggregate|TaskAggregate)\b',
      ).hasMatch(readModels.text)) {
        violations.add(
          'chat_panel_read_models.dart: retains a domain aggregate type',
        );
      }
      for (final required in [
        'ProjectScheduleReadModel',
        'ProjectWorkspaceContextReadModel',
      ]) {
        if (!readModels.text.contains('class $required')) {
          violations.add('chat_panel_read_models.dart: missing $required');
        }
      }
    }
    if (projection == null) {
      violations.add(
        'chat_panel_projection.dart: projection adapter is missing',
      );
    } else {
      for (final required in [
        'ChatPanelProjection',
        'ProjectAggregate',
        'Task',
      ]) {
        if (!projection.text.contains(required)) {
          violations.add('chat_panel_projection.dart: missing $required');
        }
      }
    }
    _expectEmpty('chat panel aggregate boundary', violations);
  });

  test('cross-feature session ports move aggregates by identity', () {
    final project = graph
        .byPath['lib/features/project/application/project_application/project_ports.dart'];
    final task = graph
        .byPath['lib/features/task/application/task_application/task_ports.dart'];
    final violations = <String>[];
    if (project == null || task == null) {
      violations.add('project/task session port files are missing');
    } else {
      final projectSession = project.text.substring(
        project.text.indexOf('updateProjectChatSessionId'),
        project.text.indexOf('abstract interface class ProjectPlanningPort'),
      );
      final taskSession = task.text.substring(
        task.text.indexOf('updateTaskChatSessionId'),
        task.text.indexOf('abstract interface class TaskPresentationPort'),
      );
      if (projectSession.contains('ProjectAggregate snapshot')) {
        violations.add(
          'project_ports.dart: session move still accepts ProjectAggregate',
        );
      }
      if (taskSession.contains('Task snapshot')) {
        violations.add(
          'task_ports.dart: session move still accepts TaskAggregate',
        );
      }
      for (final required in ['projectId', 'sourceChatSessionId']) {
        if (!projectSession.contains(required)) {
          violations.add('project_ports.dart: session move lacks $required');
        }
      }
      for (final required in ['taskId', 'sourceChatSessionId']) {
        if (!taskSession.contains(required)) {
          violations.add('task_ports.dart: session move lacks $required');
        }
      }
    }
    _expectEmpty('cross-feature session identity boundary', violations);
  });

  test('summary query ports do not expose aggregate hydration', () {
    final violations = <String>[];
    for (final path in [
      'lib/features/project/application/project_application/project_ports.dart',
      'lib/features/task/application/task_application/task_ports.dart',
    ]) {
      final source = graph.byPath[path];
      if (source == null) {
        violations.add('$path: query port file is missing');
        continue;
      }
      final marker = path.contains('/project/')
          ? 'abstract interface class ProjectSummaryQueryPort'
          : 'abstract interface class TaskSummaryQueryPort';
      final start = source.text.indexOf(marker);
      final end = source.text.indexOf(
        'abstract interface class ',
        start + marker.length,
      );
      final summary = start < 0
          ? source.text
          : source.text.substring(start, end < 0 ? source.text.length : end);
      if (summary.contains('ProjectAggregate') ||
          summary.contains('TaskAggregate') ||
          RegExp(r'Future<\s*(?:Project|Task)\??\s*>').hasMatch(summary)) {
        violations.add('$path: summary query exposes aggregate hydration');
      }
    }
    _expectEmpty('summary query boundary', violations);
  });

  test('resolved declarations enforce focused port parameter types', () async {
    final violations = <String>[];
    for (final path in [
      'lib/features/project/application/project_application/project_ports.dart',
      'lib/features/task/application/task_application/task_ports.dart',
    ]) {
      final source = graph.byPath[path]!;
      final resolved = await _resolveSource(source);
      if (resolved == null) {
        violations.add('$path: analyzer could not resolve declarations');
        continue;
      }
      for (final declaration in resolved.unit.declarations) {
        if (declaration is! ClassDeclaration) continue;
        for (final member in declaration.body.members) {
          if (member is! MethodDeclaration ||
              !member.name.lexeme.contains('ChatSessionId')) {
            continue;
          }
          for (final parameter in member.parameters?.parameters ?? const []) {
            final type = parameter.declaredFragment?.element.type;
            if (type == null) continue;
            final display = type.getDisplayString();
            if (display == 'ProjectAggregate' || display == 'TaskAggregate') {
              violations.add(
                '$path:${_line(source.text, parameter.offset)}: '
                '${member.name.lexeme} still accepts $display',
              );
            }
          }
        }
      }
    }
    _expectEmpty('resolved focused port types', violations);
  });

  test('resolved workflow declarations do not leak aggregates', () async {
    final violations = <String>[];
    const workflowPorts = <String, String>{
      'lib/features/project/application/project_application/project_workflow_port.dart':
          'ProjectWorkflowPort',
      'lib/features/task/application/task_application/task_workflow_port.dart':
          'TaskWorkflowPort',
    };
    for (final entry in workflowPorts.entries) {
      final source = graph.byPath[entry.key];
      if (source == null) {
        violations.add('${entry.key}: workflow port is missing');
        continue;
      }
      final resolved = await _resolveSource(source);
      if (resolved == null) {
        violations.add(
          '${entry.key}: analyzer could not resolve workflow port',
        );
        continue;
      }
      final declaration = resolved.unit.declarations
          .whereType<ClassDeclaration>()
          .where((item) => item.declaredFragment?.element.name == entry.value)
          .firstOrNull;
      if (declaration == null) {
        violations.add('${entry.key}: ${entry.value} declaration is missing');
        continue;
      }
      final methods = declaration.body.members.whereType<MethodDeclaration>();
      for (final method in methods) {
        final element = method.declaredFragment?.element;
        final returnType = element?.returnType.getDisplayString() ?? '';
        if (RegExp(
          r'\b(?:ProjectAggregate|TaskAggregate|Task)\b',
        ).hasMatch(returnType)) {
          violations.add(
            '${entry.key}:${_line(source.text, method.offset)}: '
            '${method.name.lexeme} returns aggregate type $returnType',
          );
        }
        for (final parameter in method.parameters?.parameters ?? const []) {
          final type = parameter.declaredFragment?.element.type;
          final display = type?.getDisplayString() ?? '';
          if (RegExp(
            r'\b(?:ProjectAggregate|TaskAggregate|Task)\b',
          ).hasMatch(display)) {
            violations.add(
              '${entry.key}:${_line(source.text, parameter.offset)}: '
              '${method.name.lexeme} accepts aggregate type $display',
            );
          }
        }
      }
    }
    for (final path in [
      'lib/features/chat/runtime/chat_session_orchestrator.dart',
      'lib/features/chat/runtime/chat_work_use_case.dart',
      'lib/features/chat/runtime/chat_project_command_coordinator.dart',
      'lib/features/chat/runtime/chat_task_command_coordinator.dart',
    ]) {
      final source = graph.byPath[path];
      if (source == null) continue;
      for (final forbidden in [
        'ProjectPlanningPort',
        'ProjectCommandPort',
        'ProjectExecutionPort',
        'TaskPlanningPort',
        'TaskExecutionPort',
        'TaskRecoveryPort',
      ]) {
        if (RegExp('\b$forbidden\b').hasMatch(source.text)) {
          violations.add(
            '$path: legacy aggregate workflow port $forbidden leaked',
          );
        }
      }
    }
    _expectEmpty('resolved aggregate-free workflow boundary', violations);
  });

  test('chat state owns explicit immutable slices and projections', () {
    final state = graph.byPath['lib/features/chat/domain/chat_state.dart']!;
    final view =
        graph.byPath['lib/features/chat/application/chat_view_state.dart']!;
    final slices =
        graph.byPath['lib/features/chat/domain/chat_state_slices.dart']!;
    final violations = <String>[];
    for (final name in [
      'ChatConversationState',
      'ChatModelSessionState',
      'ChatTaskPanelState',
      'ChatProjectPanelState',
      'ChatPersistenceState',
      'ChatTransientOperationState',
    ]) {
      if (!slices.text.contains('class $name')) {
        violations.add('chat_state_slices.dart: missing $name');
      }
    }
    for (final source in [state, view]) {
      if (RegExp(
        r'\b(?:ProjectAggregate|TaskAggregate)\b',
      ).hasMatch(source.text)) {
        violations.add('${source.path}: exposes a domain aggregate');
      }
    }
    if (!state.text.contains('ChatStateReducer')) {
      violations.add(
        'chat_state.dart: reducer is not the state transition owner',
      );
    }
    _expectEmpty('chat state slices', violations);
  });

  test(
    'wire compatibility is confined to protocol and persistence adapters',
    () {
      final violations = <String>[];
      for (final source in graph.sources) {
        if (source.path.contains('/application/contracts/') &&
            RegExp(
              r'\b(?:jsonDecode|jsonEncode|argumentsJson|resultJson)\b',
            ).hasMatch(source.text)) {
          violations.add('${source.path}: wire JSON in application contract');
        }
      }
      for (final path in [
        'lib/features/tools/application/tool_protocol_adapter.dart',
        'lib/features/chat/infrastructure/chat_panel_protocol_adapter.dart',
        'lib/features/task/application/protocol/planning_protocol_adapter.dart',
      ]) {
        if (!graph.byPath.containsKey(path)) {
          violations.add('$path: protocol adapter is missing');
        }
      }
      _expectEmpty('wire boundary ownership', violations);
    },
  );

  test('planning registries expose typed dispatch boundaries', () {
    final violations = <String>[];
    for (final path in [
      'lib/features/project/runtime/project_planning_tools.dart',
      'lib/features/task/runtime/task_planning_tools.dart',
    ]) {
      final source = graph.byPath[path];
      if (source == null) {
        violations.add('$path: planning registry is missing');
        continue;
      }
      if (!source.text.contains('Future<PlanningResponse> dispatch(') ||
          !source.text.contains('PlanningArguments arguments')) {
        violations.add('$path: dispatch does not use typed planning contracts');
      }
      final dispatchStart = source.text.indexOf(
        'Future<PlanningResponse> dispatch(',
      );
      final dispatchEnd = source.text.indexOf(
        'Map<String, dynamic> domainError',
        dispatchStart,
      );
      final dispatch = dispatchStart < 0 || dispatchEnd < 0
          ? source.text
          : source.text.substring(dispatchStart, dispatchEnd);
      if (RegExp(
        r'Future<Map<String, dynamic>>\s+dispatch',
      ).hasMatch(dispatch)) {
        violations.add('$path: dynamic map leaked through registry dispatch');
      }
      if (source.text.contains('arguments.toWire()')) {
        violations.add(
          '$path: registry converts typed arguments back to a wire map',
        );
      }
    }
    _expectEmpty('typed planning registry boundaries', violations);
  });

  test(
    'runtime wiring files contain no ignore directives or hidden contexts',
    () {
      final violations = <String>[];
      for (final source in graph.sources) {
        if (!source.path.contains('/runtime/')) continue;
        if (source.text.contains('ignore_for_file:')) {
          violations.add('${source.path}: runtime ignore directive remains');
        }
        if (RegExp(
          r'\b(?:TaskRuntimeContext|ProjectRuntimeContext|ChatRuntimeContext)\b',
        ).hasMatch(source.text)) {
          violations.add('${source.path}: mutable mega-context remains');
        }
      }
      _expectEmpty('runtime wiring hygiene', violations);
    },
  );

  test('composition and persistence invariants are explicit', () {
    final app = graph.byPath['lib/app_dependencies.dart']!.text;
    final persistence =
        graph.byPath['lib/app/modules/persistence_module.dart']!.text;
    final tasks = graph
        .byPath['lib/features/task/infrastructure/task_repository.dart']!
        .text;
    final projects = graph
        .byPath['lib/features/project/infrastructure/project_repository.dart']!
        .text;
    final violations = <String>[];
    for (final name in [
      'PersistenceModule',
      'ModelModule',
      'TaskModule',
      'ProjectModule',
      'ChatModule',
      'WorkspaceToolsModule',
    ]) {
      if (!app.contains(name)) {
        violations.add('app_dependencies.dart: missing $name');
      }
    }
    if (!persistence.contains(
      'final coordinator = WorkspacePersistenceCoordinator()',
    )) {
      violations.add(
        'persistence module does not own coordinator construction',
      );
    }
    if (RegExp(r'WorkspacePersistenceCoordinator\s*\(').hasMatch(tasks) ||
        RegExp(r'WorkspacePersistenceCoordinator\s*\(').hasMatch(projects)) {
      violations.add('repository constructs fallback coordinator');
    }
    _expectEmpty('composition/persistence ownership', violations);
  });
}
