library;

import 'package:hermes/features/chat/runtime/chat_session_orchestrator.dart';

export 'chat_session_orchestrator.dart' show ChatSessionOperations;

/// Stable compatibility name for the chat-session facade.
///
/// Session, workspace, command, persistence, and presentation orchestration
/// is implemented by [ChatSessionOrchestrator].
typedef ChatSessionRuntime = ChatSessionOrchestrator;
