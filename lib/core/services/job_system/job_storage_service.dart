import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/models/job.dart';
import 'package:hermes/core/services/job_system/job_summary.dart';
import 'package:path/path.dart' as path;

class JobStorageService {
  static const String jobsRoot = '.agent/jobs';
  static const String documentFileName = 'job.json';

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
      final file = File(path.join(entity.path, documentFileName));
      if (!await file.exists()) continue;

      try {
        final job = JobDocument.fromJson(await _readMap(file));
        if (job.schemaVersion != JobDocument.currentSchemaVersion) continue;
        if (chatSessionId != null && job.chatSessionId != chatSessionId) {
          continue;
        }
        summaries.add(
          JobSummary(
            id: job.id,
            title: job.title,
            chatSessionId: job.chatSessionId,
            status: job.status,
            updatedAt: job.updatedAt,
            currentPhaseId: job.currentStepId,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  Future<JobDocument?> loadLatestJob(
    String workspaceRoot, {
    String? chatSessionId,
  }) async {
    final jobs = await listJobs(workspaceRoot, chatSessionId: chatSessionId);
    if (jobs.isEmpty) return null;
    return loadJob(workspaceRoot, jobs.first.id, chatSessionId: chatSessionId);
  }

  Future<JobDocument?> loadJob(
    String workspaceRoot,
    String jobId, {
    String? chatSessionId,
  }) async {
    final file = File(
      path.join(_jobDirectory(workspaceRoot, jobId).path, documentFileName),
    );
    if (!await file.exists()) return null;

    final job = JobDocument.fromJson(await _readMap(file));
    if (job.schemaVersion != JobDocument.currentSchemaVersion) return null;
    if (chatSessionId != null && job.chatSessionId != chatSessionId) {
      return null;
    }
    return job;
  }

  Future<void> saveSnapshot(String workspaceRoot, JobDocument job) async {
    final dir = _jobDirectory(workspaceRoot, job.id);
    await dir.create(recursive: true);
    await _writeMap(File(path.join(dir.path, documentFileName)), job.toJson());
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
    throw const FormatException('Expected a JSON object');
  }

  Future<void> _writeMap(File file, Map<String, dynamic> map) {
    return _writeText(file, '${_encoder.convert(map)}\n');
  }

  Future<void> _writeText(File file, String content) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }
}
