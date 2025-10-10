import 'dart:async';

class ThrottledScheduler {
  final Duration interval;
  final void Function() onTick;
  Timer? _timer;

  ThrottledScheduler({
    required this.interval,
    required this.onTick,
  });

  void schedule() {
    _timer ??= Timer(interval, () {
      _timer = null;
      onTick();
    });
  }
  
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
