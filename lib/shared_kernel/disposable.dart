/// Abstract base class for services that require cleanup on shutdown.
///
/// The application dependency scope calls [dispose] on owned services in
/// reverse construction order during application shutdown. Implementations
/// should release resources such as listeners, timers, database connections,
/// and network clients.
///
/// By default, [dispose] is a no-op. Override it when the service holds
/// resources that need explicit cleanup. The method is idempotent — calling
/// it multiple times must be safe.
abstract class Disposable {
  /// Releases resources held by this service.
  ///
  /// Implementations should guard against double-disposal (e.g., with a
  /// `_disposed` flag).
  Future<void> dispose() async {}
}
