import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/sandbox_policy.dart';
import 'package:hermes/core/services/terminal_command_classifier.dart';

/// Executes a user-approved shell command on the host machine.
///
/// This is deliberately not a security sandbox. The command classifier is a
/// defense-in-depth guardrail for known dangerous patterns; approved commands
/// still run with the application's host permissions.
class HostCommandRunner {
  HostCommandRunner({
    Duration timeout = kCommandTimeout,
    this.terminationGrace = const Duration(seconds: 2),
  }) : _timeout = timeout;

  final Duration _timeout;
  final Duration terminationGrace;

  Future<Map<String, dynamic>> run({
    required String commandLine,
    required String workingDirectory,
    required String relativeWorkingDirectory,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    if (commandLine.trim().isEmpty) {
      throw WorkspaceSandboxException('Command is required.');
    }
    final blockedReason = TerminalCommandClassifier.blockedReasonForCommand(
      commandLine,
    );
    if (blockedReason != null) throw WorkspaceSandboxException(blockedReason);

    final launched = await _start(commandLine, workingDirectory);
    final process = launched.process;
    final stdout = _BoundedOutputCollector(kMaxCommandOutputBytes);
    final stderr = _BoundedOutputCollector(kMaxCommandOutputBytes);
    final stdoutSubscription = process.stdout.listen(stdout.add);
    final stderrSubscription = process.stderr.listen(stderr.add);
    final stdoutDone = stdoutSubscription.asFuture<void>();
    final stderrDone = stderrSubscription.asFuture<void>();
    final cancelled = Completer<_CommandEndReason>();
    final unregister = cancellationToken?.onCancel(() {
      if (!cancelled.isCompleted) {
        cancelled.complete(_CommandEndReason.cancelled);
      }
    });

    try {
      final reason = await Future.any([
        process.exitCode.then((_) => _CommandEndReason.exited),
        Future<_CommandEndReason>.delayed(
          _timeout,
          () => _CommandEndReason.timedOut,
        ),
        cancelled.future,
      ]);
      if (reason != _CommandEndReason.exited) await _terminate(launched);

      final exitCode = await process.exitCode;
      await _waitForOutputDrain(
        stdoutDone: stdoutDone,
        stderrDone: stderrDone,
        stdoutSubscription: stdoutSubscription,
        stderrSubscription: stderrSubscription,
      );
      if (reason == _CommandEndReason.cancelled) {
        throw const OperationCancelledException();
      }
      if (reason == _CommandEndReason.timedOut) {
        throw WorkspaceSandboxException(
          'Command timed out after ${_timeout.inSeconds} seconds.',
          code: 'command_timeout',
        );
      }
      return {
        'command': commandLine,
        'working_directory': relativeWorkingDirectory,
        'exit_code': exitCode,
        'stdout': stdout.text,
        'stderr': stderr.text,
      };
    } finally {
      unregister?.call();
    }
  }

  Future<_LaunchedHostProcess> _start(
    String commandLine,
    String workingDirectory,
  ) async {
    if (Platform.isWindows) {
      return _startDirect('cmd.exe', [
        '/d',
        '/s',
        '/c',
        commandLine,
      ], workingDirectory);
    }

    final configuredShell = Platform.environment['SHELL']?.trim();
    final shell = configuredShell == null || configuredShell.isEmpty
        ? '/bin/sh'
        : configuredShell;
    final shellArguments = ['-lc', commandLine];
    try {
      final process = await Process.start('setsid', [
        shell,
        ...shellArguments,
      ], workingDirectory: workingDirectory);
      return _LaunchedHostProcess(process, ownsProcessGroup: true);
    } on ProcessException {
      return _startDirect(shell, shellArguments, workingDirectory);
    }
  }

  Future<_LaunchedHostProcess> _startDirect(
    String executable,
    List<String> arguments,
    String workingDirectory,
  ) async {
    try {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
      return _LaunchedHostProcess(process, ownsProcessGroup: false);
    } on ProcessException catch (error) {
      throw WorkspaceSandboxException(
        'Could not start a host command process: ${error.message}',
        code: 'command_execution_unavailable',
      );
    }
  }

  Future<void> _terminate(_LaunchedHostProcess launched) async {
    await _signal(launched, 'TERM', ProcessSignal.sigterm);
    try {
      await launched.process.exitCode.timeout(terminationGrace);
    } on TimeoutException {
      // Escalation is handled below even when the parent exits during the
      // grace period. A child can outlive the parent while retaining the
      // stdout/stderr pipes, which would otherwise leave run() waiting
      // forever for EOF.
    }
    await _signal(launched, 'KILL', ProcessSignal.sigkill);
    await launched.process.exitCode;
  }

  Future<void> _waitForOutputDrain({
    required Future<void> stdoutDone,
    required Future<void> stderrDone,
    required StreamSubscription<List<int>> stdoutSubscription,
    required StreamSubscription<List<int>> stderrSubscription,
  }) async {
    try {
      await Future.wait([stdoutDone, stderrDone]).timeout(terminationGrace);
    } on TimeoutException {
      // A descendant may have inherited one of the pipes and escaped the
      // process-group cleanup. The command is already finished from the
      // runner's perspective, so do not let pipe EOF block cancellation.
      try {
        await Future.wait([
          stdoutSubscription.cancel(),
          stderrSubscription.cancel(),
        ]).timeout(terminationGrace);
      } on TimeoutException {
        // Stream cancellation is best-effort; the command result/error must
        // still be allowed to reach the caller.
      }
    }
  }

  Future<void> _signal(
    _LaunchedHostProcess launched,
    String signal,
    ProcessSignal fallbackSignal,
  ) async {
    if (launched.ownsProcessGroup && !Platform.isWindows) {
      try {
        final result = await Process.run('kill', [
          '-$signal',
          '--',
          '-${launched.process.pid}',
        ]);
        if (result.exitCode == 0) return;
      } on ProcessException {
        // Fall through to signalling the direct process.
      }
    }
    launched.process.kill(fallbackSignal);
  }
}

class _LaunchedHostProcess {
  const _LaunchedHostProcess(this.process, {required this.ownsProcessGroup});

  final Process process;
  final bool ownsProcessGroup;
}

enum _CommandEndReason { exited, timedOut, cancelled }

class _BoundedOutputCollector {
  _BoundedOutputCollector(this.limit);

  final int limit;
  final List<int> _bytes = [];
  bool _truncated = false;

  void add(List<int> chunk) {
    final remaining = limit - _bytes.length;
    if (remaining > 0) _bytes.addAll(chunk.take(remaining));
    if (chunk.length > remaining) _truncated = true;
  }

  String get text {
    final value = utf8.decode(_bytes, allowMalformed: true);
    return _truncated ? '$value\n... output truncated ...' : value;
  }
}
