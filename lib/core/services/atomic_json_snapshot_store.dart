import 'dart:convert';
import 'dart:io';

class SnapshotCorruptionException implements Exception {
  const SnapshotCorruptionException(this.path, [this.cause]);

  final String path;
  final Object? cause;

  @override
  String toString() =>
      'Snapshot is corrupt: $path${cause == null ? '' : ' ($cause)'}';
}

/// Crash-resistant JSON object storage with one last-known-good backup.
class AtomicJsonSnapshotStore {
  static int _temporarySequence = 0;

  const AtomicJsonSnapshotStore();

  File backupFor(File primary) => File('${primary.path}.bak');

  Future<Map<String, dynamic>?> readMap(
    File primary, {
    bool Function(Map<String, dynamic> map)? isValid,
  }) async {
    Object? primaryError;
    if (await primary.exists()) {
      try {
        final map = await _decodeFile(primary);
        if (isValid != null && !isValid(map)) {
          throw const FormatException('Snapshot object is invalid');
        }
        return map;
      } catch (error) {
        primaryError = error;
      }
    }

    final backup = backupFor(primary);
    if (await backup.exists()) {
      try {
        final recovered = await _decodeFile(backup);
        if (isValid != null && !isValid(recovered)) {
          throw const FormatException('Backup snapshot object is invalid');
        }
        await _replace(
          primary,
          '${const JsonEncoder.withIndent('  ').convert(recovered)}\n',
        );
        return recovered;
      } catch (backupError) {
        throw SnapshotCorruptionException(
          primary.path,
          primaryError ?? backupError,
        );
      }
    }

    if (primaryError != null) {
      throw SnapshotCorruptionException(primary.path, primaryError);
    }
    return null;
  }

  Future<void> writeMap(
    File primary,
    Map<String, dynamic> map, {
    bool Function(Map<String, dynamic> map)? isValid,
  }) async {
    final content = '${const JsonEncoder.withIndent('  ').convert(map)}\n';
    _decodeContent(content);
    await primary.parent.create(recursive: true);

    if (await primary.exists()) {
      try {
        final previous = await primary.readAsString();
        final previousMap = _decodeContent(previous);
        if (isValid != null && !isValid(previousMap)) {
          throw const FormatException('Previous snapshot object is invalid');
        }
        await _replace(backupFor(primary), previous);
      } catch (_) {
        // Never replace a valid backup with a corrupt primary.
      }
    }

    await _replace(primary, content);
  }

  Future<Map<String, dynamic>> _decodeFile(File file) async {
    return _decodeContent(await file.readAsString());
  }

  Map<String, dynamic> _decodeContent(String content) {
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('Expected a JSON object');
  }

  Future<void> _replace(File destination, String content) async {
    final sequence = _temporarySequence++;
    final temporary = File(
      '${destination.path}.tmp.${pid}_${DateTime.now().microsecondsSinceEpoch}_$sequence',
    );
    try {
      await temporary.writeAsString(content, flush: true);
      _decodeContent(await temporary.readAsString());
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
