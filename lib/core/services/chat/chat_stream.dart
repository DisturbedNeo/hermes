import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/enums/stream_state.dart';

class ChatStream<T> extends ChangeNotifier {
  StreamState _state = StreamState.idle;
  StreamSubscription<T>? _sub;

  StreamState get state => _state;
  bool get isStreaming => _state == StreamState.streaming;

  void setState(StreamState s) {
    if (_state != s) {
      _state = s;
      notifyListeners();
    }
  }

  void attach(StreamSubscription<T> sub) {
    _sub = sub;
    setState(StreamState.streaming);
  }

  Future<void> stop({ StreamState next = StreamState.idle }) async {
    final s = _sub;
    _sub = null;
    await s?.cancel();
    setState(next);
  }
}
