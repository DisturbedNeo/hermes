import 'dart:async';
import 'dart:io';

class LlamaServerHandle {
  final Process process;
  final StreamSubscription stdoutSub;
  final StreamSubscription stderrSub;

  LlamaServerHandle({
    required this.process,
    required this.stdoutSub,
    required this.stderrSub,
  });

  Future<void> stop() async {
    _sendSignalSafe(process, ProcessSignal.sigint);

    await Future.delayed(const Duration(milliseconds: 400));

    _sendSignalSafe(process, ProcessSignal.sigterm);

    await Future.delayed(const Duration(milliseconds: 300));
    _sendSignalSafe(process, ProcessSignal.sigkill);

    await stdoutSub.cancel();
    await stderrSub.cancel();
  }

  void _sendSignalSafe(Process p, ProcessSignal sig) {
    try {
      p.kill(sig);
    } catch (_) {}
  }
}
