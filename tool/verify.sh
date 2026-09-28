#!/usr/bin/env bash
set -euo pipefail

dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed lib test
dart analyze
flutter test
# dart_mappable currently emits a trailing blank line in generated outputs;
# check all handwritten sources while allowing that generator detail.
git diff --check -- . ':(exclude)lib/core/serialization/mappers.init.dart' ':(exclude,glob)**/*.mapper.dart'
