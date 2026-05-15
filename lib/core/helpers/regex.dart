String? regexError(String pattern) {
  try {
    RegExp(pattern, multiLine: true);
    return null;
  } catch (e) {
    return e.toString();
  }
}

bool regexMatches(String pattern, String content) {
  return RegExp(pattern, multiLine: true).hasMatch(content);
}
