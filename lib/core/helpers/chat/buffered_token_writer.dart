import 'dart:async';

import 'package:hermes/core/helpers/chat/assistant_ops.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/services/chat/message_store.dart';

/// Publishes streamed tokens in small batches to bound UI notification work.
class BufferedTokenWriter {
  BufferedTokenWriter({
    required MessageStore messageStore,
    this.interval = const Duration(milliseconds: 50),
    this.onFlush,
  }) : _messageStore = messageStore;

  final MessageStore _messageStore;
  final Duration interval;
  final void Function()? onFlush;
  final List<ChatToken> _pending = [];
  Timer? _timer;
  bool _disposed = false;

  bool get hasPending => _pending.isNotEmpty;

  void add(ChatToken token) {
    if (_disposed) return;
    _pending.add(token);
    _timer ??= Timer(interval, flush);
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final batch = List<ChatToken>.of(_pending);
    _pending.clear();
    _messageStore.appendTokens(batch);
    onFlush?.call();
  }

  void dispose() {
    if (_disposed) return;
    flush();
    _disposed = true;
  }
}
