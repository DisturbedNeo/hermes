/// Framework-neutral notification capability for application-facing views.
///
/// Flutter adapters may implement this with ChangeNotifier, while core and
/// application contracts remain independent of the UI framework.
abstract interface class NotificationPort {
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}
