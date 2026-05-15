import 'package:flutter/foundation.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/services/chat/chat_client.dart';

/// A lightweight service that spawns ephemeral subagents to extract specific
/// information from file contents without ingesting the entire file into the
/// main agent's context.
class SubagentService {
  final ChatClient Function() _chatClientFactory;

  SubagentService({required ChatClient Function() chatClientFactory})
    : _chatClientFactory = chatClientFactory;

  /// Extracts specific information from [fileContent] based on the
  /// [extractionRequest]. The subagent is instructed to return only the
  /// requested information with no superfluous text.
  Future<String> extract({
    required String fileContent,
    required String extractionRequest,
    String filePath = '',
    int maxTokens = 2048,
  }) async {
    final client = _chatClientFactory();

    final systemPrompt = '''You are a precise information extraction agent. Your ONLY job is to return the exact information requested by the user. You must NEVER include:
- Greetings or pleasantries
- Explanations of what you found
- File paths unless specifically requested
- Code formatting markers (like ```json) unless the request asks for formatted output
- Any text beyond exactly what was asked for

If the requested information is not present in the file, return: "NOT_FOUND"

Return ONLY the extracted information. Be concise and direct.''';

    final userPrompt = '''File path: $filePath

Extract the following from this file:

$extractionRequest

Here is the file content:
--- FILE CONTENT ---
$fileContent
--- END FILE CONTENT ---''';

    try {
      final response = await client.completeMessage(
        messages: [
          ChatMessage(role: 'system', content: systemPrompt),
          ChatMessage(role: 'user', content: userPrompt),
        ],
        extraParams: {
          'max_tokens': maxTokens,
          'temperature': 0.1,
        },
      );

      return response.trim();
    } catch (e) {
      if (kDebugMode) {
        print('[SubagentService] Extraction failed: $e');
      }
      return 'EXTRACTION_ERROR: $e';
    }
  }

  /// Returns a summary of the file content. Useful for quickly understanding
  /// what a file contains without reading it in full.
  Future<String> summarize({
    required String fileContent,
    String filePath = '',
    int maxTokens = 1024,
  }) async {
    return extract(
      fileContent: fileContent,
      extractionRequest:
          'Provide a concise summary of what this file contains. Include the main purpose, key components, and important details. Keep it under 200 words.',
      filePath: filePath,
      maxTokens: maxTokens,
    );
  }

  /// Returns a specific code snippet from the file matching the description.
  Future<String> findSnippet({
    required String fileContent,
    required String description,
    String filePath = '',
    int maxTokens = 1024,
  }) async {
    return extract(
      fileContent: fileContent,
      extractionRequest:
          'Find the code snippet that matches this description: "$description". Return ONLY the relevant code snippet with its surrounding context (at least 3 lines before and after). Do not include any explanation.',
      filePath: filePath,
      maxTokens: maxTokens,
    );
  }

  /// Returns specific information about the file structure or contents.
  Future<String> extractInfo({
    required String fileContent,
    required String extractionRequest,
    String filePath = '',
    int maxTokens = 2048,
  }) async {
    return extract(
      fileContent: fileContent,
      extractionRequest: extractionRequest,
      filePath: filePath,
      maxTokens: maxTokens,
    );
  }
}
