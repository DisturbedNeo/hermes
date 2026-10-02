#!/usr/bin/env bash

set -euo pipefail

workspace_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$workspace_dir"

echo "== Regenerating mappers =="
dart run build_runner build

echo "== Checking formatting =="
dart format --output=none --set-exit-if-changed lib test

echo "== Analyzing Dart =="
flutter analyze

echo "== Running architecture suite =="
flutter test test/architecture/architecture_test.dart

echo "== Running full Flutter test suite =="
flutter test

echo "== Checking diff whitespace =="
# Generated mapper output is checked by the build step. The package initializer
# is generated too and the current builder emits a harmless blank line at EOF;
# exclude generated output from whitespace diagnostics.
git diff --check -- . \
  ':(exclude)lib/app/mappers.init.dart' \
  ':(exclude)lib/**/*.mapper.dart'

echo "Verification passed."
