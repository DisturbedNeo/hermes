import 'package:hermes/features/chat/runtime/chat_controller.dart';

export 'package:hermes/features/chat/runtime/chat_controller.dart';

/// Public chat application entry point.
///
/// The execution engine is composed in the runtime layer; this alias keeps
/// the application boundary free of platform and persistence dependencies.
typedef ChatController = ChatRuntimeController;
