import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/features/workspace/domain/workspace.dart';

/// Small state and callback surface required by [ChatSessionManager].
///
/// The streaming/session engine deliberately depends on this policy boundary
/// rather than on the UI-facing ChatRuntimeController. This keeps session execution
/// usable with a deterministic host in tests and prevents the stream engine
/// from reaching into unrelated chat persistence or task state.
abstract interface class ChatSessionHost {
  WorkspaceAttachment? get workspace;

  ModelConfigurationSnapshot? get currentModelSnapshot;

  int? get sessionDiagnosticsContextLimit;

  List<String> get defaultToolIds;

  bool get workspaceToolsEnabled;

  String get taskModelOutputText;
  set taskModelOutputText(String value);

  String get taskModelOutputReasoning;
  set taskModelOutputReasoning(String value);

  void markWorkspaceChanged();

  void sessionNotifyListeners();

  void requestContextEstimateUpdate({bool immediate = false});

  String buildSystemPrompt({String? currentUserRequest});

  String? sessionTaskModelOutputLabel();

  void setSessionTaskModelOutputLabel(String? value);

  String? sessionTaskModelOutputTextSection();

  void setSessionTaskModelOutputTextSection(String? value);

  String? sessionTaskModelOutputReasoningLabel();

  void setSessionTaskModelOutputReasoningLabel(String? value);
}
