import 'dart:async';
import 'dart:io';

/// Thrown when llama-server startup is cancelled (e.g., by a new start request).
class LlamaServerStartupCancelled implements Exception {
  const LlamaServerStartupCancelled();

  @override
  String toString() => 'llama-server startup cancelled';
}

/// Checks the health of a llama-server instance using HTTP GET /health.
///
/// Polls the server with exponential backoff until it responds with 200 OK,
/// times out, or the process exits. Designed to be used as a standalone
/// utility for any long-running server startup sequence.
class ServerHealthChecker {
  static const Duration _defaultHealthRequestTimeout = Duration(seconds: 2);
  static const Duration _defaultStartupStallTimeout = Duration(minutes: 2);

  /// The base URL of the server to check.
  final Uri baseUrl;

  /// The process whose exit code should be monitored.
  final Process process;

  /// Timeout for individual health-check HTTP requests.
  final Duration healthRequestTimeout;

  /// Maximum time without progress before declaring a stall.
  final Duration startupStallTimeout;

  /// Optional getter for recent process output to include in failure messages.
  final String Function()? recentOutputGetter;

  ServerHealthChecker({
    required this.baseUrl,
    required this.process,
    this.healthRequestTimeout = _defaultHealthRequestTimeout,
    this.startupStallTimeout = _defaultStartupStallTimeout,
    this.recentOutputGetter,
  });

  /// Waits until the server responds with HTTP 200 on `/health`.
  ///
  /// Throws [StateError] if the process exits before becoming healthy or
  /// if the startup appears stalled (no output for too long).
  /// Returns `true` when the server is ready.
  Future<bool> waitForReady({
    required bool Function() isCancelled,
  }) async {
    final client = HttpClient();
    Object? lastError;
    var processExited = false;
    int? processExitCode;
    final exitCode = process.exitCode;

    unawaited(
      exitCode.then((code) {
        processExited = true;
        processExitCode = code;
      }),
    );

    var delay = const Duration(milliseconds: 100);
    var lastProgressAt = DateTime.now();
    final maxDelay = const Duration(seconds: 1);

    try {
      while (true) {
        if (isCancelled()) {
          throw const LlamaServerStartupCancelled();
        }

        if (processExited) {
          final message =
              'llama-server exited before it was ready (exit code $processExitCode)';
          throw StateError(_formatFailure(message));
        }

        try {
          final req = await client
              .getUrl(baseUrl.replace(path: '/health'))
              .timeout(healthRequestTimeout);
          final res = await req.close().timeout(healthRequestTimeout);

          if (res.statusCode == 200) {
            await res.drain();
            return true;
          }

          if (res.statusCode == 503) {
            lastProgressAt = DateTime.now();
          }

          lastError = 'health check returned HTTP ${res.statusCode}';
          await res.drain();
        } catch (e) {
          lastError = e;
        }

        if (DateTime.now().difference(lastProgressAt) > startupStallTimeout) {
          final message =
              'llama-server startup appears stalled. Last readiness error: $lastError';
          throw StateError(_formatFailure(message));
        }

        await Future.any<void>([Future.delayed(delay), exitCode.then((_) {})]);

        final nextDelayMs = (delay.inMilliseconds * 1.5).round();
        delay = Duration(
          milliseconds: nextDelayMs > maxDelay.inMilliseconds
              ? maxDelay.inMilliseconds
              : nextDelayMs,
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Formats a failure message with optional recent process output.
  String _formatFailure(String message) {
    final recentOutput = recentOutputGetter?.call() ?? '';
    return _buildFailureMessage(message, recentOutput: recentOutput);
  }

  /// Formats a user-friendly failure message including recent process output.
  static String _buildFailureMessage(
    String message, {
    required String recentOutput,
  }) {
    if (recentOutput.isEmpty) return message;
    return '$message\nRecent llama-server output:\n$recentOutput';
  }
}
