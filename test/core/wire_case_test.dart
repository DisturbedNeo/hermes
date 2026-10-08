import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/wire_case.dart';

void main() {
  test(
    'converts nested model values to snake_case without changing values',
    () {
      expect(
        snakeCaseWire({
          'workspaceProfile': {
            'treePaths': ['lib/'],
            'requiredContextIssues': [
              {'sourceId': 'workspace:README.md'},
            ],
          },
          'already_snake': true,
        }),
        {
          'workspace_profile': {
            'tree_paths': ['lib/'],
            'required_context_issues': [
              {'source_id': 'workspace:README.md'},
            ],
          },
          'already_snake': true,
        },
      );
    },
  );
}
