import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/project/application/project_application/project_ports.dart';
import 'package:hermes/shared_kernel/project.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/shared_kernel/task_summary.dart';
import 'package:hermes/features/workspace/domain/workspace.dart';

class _FakeTaskPort implements TaskQueryPort {
  final calls = <Symbol>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    if (invocation.memberName == #listTasks) {
      return Future<List<TaskSummary>>.value(const []);
    }
    throw UnsupportedError('Unexpected task call: ${invocation.memberName}');
  }
}

class _FakeProjectPort implements ProjectQueryPort {
  final calls = <Symbol>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    if (invocation.memberName == #listProjects) {
      return Future<List<ProjectSummary>>.value(const []);
    }
    throw UnsupportedError('Unexpected project call: ${invocation.memberName}');
  }
}

class _ChatPortProbe {
  const _ChatPortProbe({required this.tasks, required this.projects});

  final TaskQueryPort tasks;
  final ProjectQueryPort projects;

  Future<List<TaskSummary>> listTasks(WorkspaceAttachment workspace) =>
      tasks.listTasks(workspace);

  Future<List<ProjectSummary>> listProjects(WorkspaceAttachment workspace) =>
      projects.listProjects(workspace);
}

void main() {
  test(
    'chat orchestration can be exercised with fake task and project ports',
    () async {
      final taskPort = _FakeTaskPort();
      final projectPort = _FakeProjectPort();
      final probe = _ChatPortProbe(tasks: taskPort, projects: projectPort);
      final workspace = WorkspaceAttachment(
        rootPath: '/tmp/chat-port-probe',
        displayName: 'Probe',
        lastOpenedAt: DateTime(2026),
      );

      expect(await probe.listTasks(workspace), isEmpty);
      expect(await probe.listProjects(workspace), isEmpty);
      expect(taskPort.calls, contains(#listTasks));
      expect(projectPort.calls, contains(#listProjects));
    },
  );
}
