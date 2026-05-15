import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/services/job_system/job_summary.dart';
import 'package:path/path.dart' as path;

class JobStorageService {
  static const String jobsRoot = '.agent/jobs';

  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

  Future<List<JobSummary>> listJobs(
    String workspaceRoot, {
    String? chatSessionId,
  }) async {
    final root = Directory(path.join(workspaceRoot, jobsRoot));
    if (!await root.exists()) return const [];

    final summaries = <JobSummary>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final stateFile = File(path.join(entity.path, 'job-state.yaml'));
      final specFile = File(path.join(entity.path, 'job-spec.yaml'));
      if (!await stateFile.exists() || !await specFile.exists()) continue;

      try {
        final spec = JobSpec.fromJson(await _readMap(specFile));
        final state = JobState.fromJson(await _readMap(stateFile));
        if (chatSessionId != null && state.chatSessionId != chatSessionId) {
          continue;
        }
        summaries.add(
          JobSummary(
            id: spec.id,
            title: spec.title,
            chatSessionId: state.chatSessionId,
            status: state.status,
            updatedAt: state.updatedAt,
            currentPhaseId: state.currentPhaseId,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  Future<JobSnapshot?> loadLatestJob(
    String workspaceRoot, {
    String? chatSessionId,
  }) async {
    final jobs = await listJobs(workspaceRoot, chatSessionId: chatSessionId);
    if (jobs.isEmpty) return null;
    return loadJob(workspaceRoot, jobs.first.id, chatSessionId: chatSessionId);
  }

  Future<JobSnapshot?> loadJob(
    String workspaceRoot,
    String jobId, {
    String? chatSessionId,
  }) async {
    final dir = _jobDirectory(workspaceRoot, jobId);
    final taskBriefFile = File(path.join(dir.path, 'task-brief.yaml'));
    final specFile = File(path.join(dir.path, 'job-spec.yaml'));
    final stateFile = File(path.join(dir.path, 'job-state.yaml'));

    if (!await taskBriefFile.exists() ||
        !await specFile.exists() ||
        !await stateFile.exists()) {
      return null;
    }

    final snapshot = JobSnapshot(
      taskBrief: TaskBrief.fromJson(await _readMap(taskBriefFile)),
      spec: JobSpec.fromJson(await _readMap(specFile)),
      state: JobState.fromJson(await _readMap(stateFile)),
    );
    if (chatSessionId != null &&
        snapshot.state.chatSessionId != chatSessionId) {
      return null;
    }
    return snapshot;
  }

  Future<void> saveSnapshot(String workspaceRoot, JobSnapshot snapshot) async {
    final dir = _jobDirectory(workspaceRoot, snapshot.spec.id);
    await dir.create(recursive: true);
    await _writeMap(
      File(path.join(dir.path, 'task-brief.yaml')),
      snapshot.taskBrief.toJson(),
    );
    await _writeMap(
      File(path.join(dir.path, 'job-spec.yaml')),
      snapshot.spec.toJson(),
    );
    await _writeMap(
      File(path.join(dir.path, 'job-state.yaml')),
      snapshot.state.toJson(),
    );
    await _writeText(
      File(path.join(dir.path, 'refined-prompt.md')),
      _renderTaskBrief(snapshot.taskBrief),
    );
  }

  Future<bool> deleteJob(String workspaceRoot, String jobId) async {
    final root = Directory(path.join(workspaceRoot, jobsRoot));
    final dir = _jobDirectory(workspaceRoot, jobId);
    _throwIfOutsideJobsRoot(root, dir);
    if (!await dir.exists()) return false;
    await dir.delete(recursive: true);
    return true;
  }

  Future<int> deleteJobsForChatSession(
    String workspaceRoot, {
    required String chatSessionId,
  }) async {
    final jobs = await listJobs(workspaceRoot, chatSessionId: chatSessionId);
    var deleted = 0;
    for (final job in jobs) {
      if (await deleteJob(workspaceRoot, job.id)) deleted++;
    }
    return deleted;
  }

  Future<int> deleteOrphanedChatJobs(
    String workspaceRoot, {
    required Set<String> retainedChatSessionIds,
  }) async {
    final jobs = await listJobs(workspaceRoot);
    var deleted = 0;
    for (final job in jobs) {
      final chatSessionId = job.chatSessionId;
      if (chatSessionId == null ||
          retainedChatSessionIds.contains(chatSessionId)) {
        continue;
      }
      if (await deleteJob(workspaceRoot, job.id)) deleted++;
    }
    return deleted;
  }

  Future<void> saveReview(
    String workspaceRoot,
    String jobId,
    String phaseId,
    ReviewResult review,
  ) async {
    final dir = Directory(
      path.join(_jobDirectory(workspaceRoot, jobId).path, 'reviews'),
    );
    await dir.create(recursive: true);
    await _writeMap(
      File(path.join(dir.path, 'review-$phaseId.yaml')),
      review.toJson(),
    );
  }

  Future<void> saveLog(
    String workspaceRoot,
    String jobId,
    String name,
    String content,
  ) async {
    final dir = Directory(
      path.join(_jobDirectory(workspaceRoot, jobId).path, 'logs'),
    );
    await dir.create(recursive: true);
    await _writeText(File(path.join(dir.path, name)), content);
  }

  String jobRelativePath(String jobId, String fileName) {
    return path.posix.join(jobsRoot, jobId, fileName);
  }

  Directory _jobDirectory(String workspaceRoot, String jobId) {
    return Directory(path.join(workspaceRoot, jobsRoot, jobId));
  }

  void _throwIfOutsideJobsRoot(Directory root, Directory dir) {
    final rootPath = path.normalize(path.absolute(root.path));
    final dirPath = path.normalize(path.absolute(dir.path));
    if (!path.isWithin(rootPath, dirPath)) {
      throw ArgumentError.value(dir.path, 'jobId', 'Job path is invalid');
    }
  }

  Future<Map<String, dynamic>> _readMap(File file) async {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('Expected a JSON/YAML object');
  }

  Future<void> _writeMap(File file, Map<String, dynamic> map) {
    return _writeText(file, '${_encoder.convert(map)}\n');
  }

  Future<void> _writeText(File file, String content) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  String _renderTaskBrief(TaskBrief brief) {
    final buffer = StringBuffer()
      ..writeln('# ${brief.title}')
      ..writeln()
      ..writeln('## Objective')
      ..writeln(brief.objective)
      ..writeln()
      ..writeln('## Success Criteria');
    for (final item in brief.successCriteria) {
      buffer.writeln('- $item');
    }
    buffer
      ..writeln()
      ..writeln('## Constraints');
    for (final item in brief.constraints) {
      buffer.writeln('- $item');
    }
    buffer
      ..writeln()
      ..writeln('## Assumptions');
    for (final item in brief.assumptions) {
      buffer.writeln('- $item');
    }
    return buffer.toString();
  }
}
