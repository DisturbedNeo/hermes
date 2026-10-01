import 'package:hermes/core/json_parsing.dart';
import 'package:hermes/core/model_json.dart';
import 'package:hermes/features/task/application/contracts/question_policy_service.dart';

/// Decodes model/user-question wire values at the task protocol boundary.
class QuestionProtocolAdapter {
  const QuestionProtocolAdapter();

  AgentQuestion? decode(Object? value) {
    if (value == null) return null;
    if (value is Map) return ModelJson.decode<AgentQuestion>(value);
    final question = jsonString(value).trim();
    if (question.isEmpty) return null;
    return AgentQuestion.fromText(question);
  }
}
