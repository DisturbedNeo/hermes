import 'dart:io';

import 'package:path/path.dart' as p;

import 'file.dart';

/// Resolves the path to the `llama-server` executable within a given directory.
///
/// Searches common build output locations in order of preference:
/// 1. `llama-server` / `llama-server.exe` in the repo root
/// 2. `build/bin/llama-server` variants (CMake layouts)
/// 3. `bin/llama-server` variants
///
/// Returns `null` if no executable is found. On non-Windows platforms,
/// ensures the file has execute permission before returning its path.
Future<String?> resolveLlamaServerExecutable(String llamaCppDir) async {
  final candidates = <String>[
    // make / default in repo root
    p.join(llamaCppDir, 'llama-server'),
    p.join(llamaCppDir, 'llama-server.exe'),
    // common CMake layouts
    p.join(llamaCppDir, 'build', 'bin', 'llama-server'),
    p.join(llamaCppDir, 'build', 'bin', 'llama-server.exe'),
    p.join(llamaCppDir, 'build', 'bin', 'Release', 'llama-server.exe'),
    p.join(llamaCppDir, 'bin', 'llama-server'),
    p.join(llamaCppDir, 'bin', 'llama-server.exe'),
  ];

  for (final path in candidates) {
    final f = File(path);

    if (await f.exists()) {
      if (!Platform.isWindows && !await isExecutable(f)) {
        try {
          await Process.run('chmod', ['+x', f.path]);
        } catch (_) {}
      }

      return f.path;
    }
  }

  return null;
}
