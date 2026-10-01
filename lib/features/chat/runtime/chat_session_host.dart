import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

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
  void dispatchTaskModelOutputText(String value);
  void appendTaskModelOutputText(String value);

  String get taskModelOutputReasoning;
  void dispatchTaskModelOutputReasoning(String value);
  void appendTaskModelOutputReasoning(String value);

  void markWorkspaceChanged();

  void sessionNotifyListeners();

  void requestContextEstimateUpdate({bool immediate = false});

  String buildSystemPrompt({String? currentUserRequest});

  String? sessionTaskModelOutputLabel();

  void updateSessionTaskModelOutputLabel(String? value);

  String? sessionTaskModelOutputTextSection();

  void updateSessionTaskModelOutputTextSection(String? value);

  String? sessionTaskModelOutputReasoningLabel();

  void updateSessionTaskModelOutputReasoningLabel(String? value);
}
