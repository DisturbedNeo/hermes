import 'package:hermes/core/services/cancellation_token.dart';

/// Central cancellation boundary for UI-triggered task and project commands.
///
/// ChatService remains responsible for presentation state, while this object
/// owns the token identity and prevents a nested command from accidentally
/// replacing the token used by the active operation.
class ChatCommandCoordinator {
  CancellationToken? _activeToken;

  bool get isActive => _activeToken != null;
  CancellationToken? get activeToken => _activeToken;

  CancellationToken begin({bool reuseExisting = false}) {
    if (reuseExisting && _activeToken != null) return _activeToken!;
    final token = CancellationToken();
    _activeToken = token;
    return token;
  }

  void end(CancellationToken token) {
    if (identical(_activeToken, token)) _activeToken = null;
  }

  Future<void> cancel() async {
    final token = _activeToken;
    if (token != null) await token.cancel();
  }
}
