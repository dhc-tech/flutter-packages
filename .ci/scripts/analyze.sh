#!/usr/bin/env bash
# Runs formatting validation and strict static analysis across all packages.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "🎨 Validating Dart code formatting..."
dart format --output=none --set-exit-if-changed "$REPO_ROOT/packages"

echo "🔍 Running strict static analysis (--fatal-infos)..."
for PKG_DIR in "$REPO_ROOT"/packages/*; do
  if [ -d "$PKG_DIR" ]; then
    PKG_NAME=$(basename "$PKG_DIR")
    echo "  -> Analyzing $PKG_NAME..."
    (
      cd "$PKG_DIR"
      if grep -q "sdk: flutter" pubspec.yaml; then
        flutter analyze --fatal-infos
      else
        dart analyze --fatal-infos
      fi
    )
  fi
done

echo "✅ All packages passed analysis with zero warnings and zero fatal infos!"
