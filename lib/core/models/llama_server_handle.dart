import 'dart:async';
import 'dart:io';

class LlamaServerHandle {
  final Process process;
  final StreamSubscription stdoutSub;
  final StreamSubscription stderrSub;
  final Duration interruptGrace;
  final Duration terminateGrace;
  final Duration killGrace;
  Future<void>? _stopping;

  LlamaServerHandle({
    required this.process,
    required this.stdoutSub,
    required this.stderrSub,
    this.interruptGrace = const Duration(seconds: 2),
    this.terminateGrace = const Duration(seconds: 2),
    this.killGrace = const Duration(seconds: 1),
  });

  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    try {
      if (await _exitsWithin(Duration.zero)) return;
      _sendSignalSafe(process, ProcessSignal.sigint);
      if (await _exitsWithin(interruptGrace)) return;
      _sendSignalSafe(process, ProcessSignal.sigterm);
      if (await _exitsWithin(terminateGrace)) return;
      _sendSignalSafe(process, ProcessSignal.sigkill);
      await _exitsWithin(killGrace);
    } finally {
      await Future.wait([stdoutSub.cancel(), stderrSub.cancel()]);
    }
  }

  Future<bool> _exitsWithin(Duration timeout) async {
    try {
      await process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      return true;
    }
  }

  void _sendSignalSafe(Process p, ProcessSignal sig) {
    try {
      p.kill(sig);
    } catch (_) {}
  }
}
