import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class WorkspaceService extends ChangeNotifier {
  static const String _recentWorkspacesKey = 'recent_workspaces';
  static const int _maxRecentWorkspaces = 12;

  final WorkspaceSandbox sandbox;
  final Future<SharedPreferences> _prefs;

  WorkspaceService({
    WorkspaceSandbox? sandbox,
    Future<SharedPreferences>? prefs,
  }) : sandbox = sandbox ?? WorkspaceSandbox(),
       _prefs = prefs ?? SharedPreferences.getInstance();

  Future<WorkspaceAttachment> attach(String folderPath) async {
    final canonical = await sandbox.canonicalRoot(folderPath);
    final workspace = WorkspaceAttachment(
      rootPath: canonical,
      displayName: path.basename(canonical),
      lastOpenedAt: DateTime.now(),
    );
    await remember(workspace);
    return workspace;
  }

  Future<WorkspaceAttachment> restore({
    required String rootPath,
    required String displayName,
    required DateTime lastOpenedAt,
    required bool commandExecutionApproved,
  }) async {
    final exists = await Directory(rootPath).exists();
    if (!exists) {
      return WorkspaceAttachment(
        rootPath: rootPath,
        displayName: displayName,
        lastOpenedAt: lastOpenedAt,
        missing: true,
        commandExecutionApproved: commandExecutionApproved,
      );
    }

    final canonical = await sandbox.canonicalRoot(rootPath);
    final restored = WorkspaceAttachment(
      rootPath: canonical,
      displayName: displayName.isEmpty ? path.basename(canonical) : displayName,
      lastOpenedAt: DateTime.now(),
      commandExecutionApproved: commandExecutionApproved,
    );
    await remember(restored);
    return restored;
  }

  Future<List<WorkspaceAttachment>> recentWorkspaces() async {
    final raw = (await _prefs).getString(_recentWorkspacesKey);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map((item) {
          final rootPath = item['rootPath'] as String?;
          if (rootPath == null || rootPath.isEmpty) return null;
          return WorkspaceAttachment(
            rootPath: rootPath,
            displayName:
                item['displayName'] as String? ?? path.basename(rootPath),
            lastOpenedAt:
                DateTime.tryParse(item['lastOpenedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
          );
        })
        .whereType<WorkspaceAttachment>()
        .toList();
  }

  Future<void> remember(WorkspaceAttachment workspace) async {
    final existing = await recentWorkspaces();
    final next = <WorkspaceAttachment>[
      workspace.copyWith(lastOpenedAt: DateTime.now(), missing: false),
      ...existing.where((item) => item.rootPath != workspace.rootPath),
    ].take(_maxRecentWorkspaces).toList();

    await (await _prefs).setString(
      _recentWorkspacesKey,
      jsonEncode(
        next.map((item) {
          return {
            'rootPath': item.rootPath,
            'displayName': item.displayName,
            'lastOpenedAt': item.lastOpenedAt.toIso8601String(),
          };
        }).toList(),
      ),
    );
    notifyListeners();
  }
}
