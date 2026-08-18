#!/usr/bin/env bash
# Official multi-package command runner for DHC Tech Flutter Packages.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMMAND="$1"
shift || true

echo "📦 Running '$COMMAND' across all packages in $REPO_ROOT/packages..."

for PKG_DIR in "$REPO_ROOT"/packages/*; do
  if [ -d "$PKG_DIR" ]; then
    PKG_NAME=$(basename "$PKG_DIR")
    echo "────────────────────────────────────────"
    echo "🚀 [$PKG_NAME] Running: $COMMAND $@"
    echo "────────────────────────────────────────"
    (
      cd "$PKG_DIR"
      if grep -q "sdk: flutter" pubspec.yaml; then
        flutter $COMMAND "$@"
      else
        dart $COMMAND "$@"
      fi
    )
  fi
done

echo "✅ All packages passed successfully!"
