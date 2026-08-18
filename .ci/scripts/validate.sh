#!/usr/bin/env bash
# Validates repository health, licenses, changelogs, and package integrity.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "🛡️ Validating repository licenses and structure..."

for PKG_DIR in "$REPO_ROOT"/packages/*; do
  if [ -d "$PKG_DIR" ]; then
    PKG_NAME=$(basename "$PKG_DIR")
    
    # Verify LICENSE exists
    if [ ! -f "$PKG_DIR/LICENSE" ]; then
      echo "❌ Error: Missing LICENSE in $PKG_NAME"
      exit 1
    fi

    # Verify CHANGELOG.md exists
    if [ ! -f "$PKG_DIR/CHANGELOG.md" ]; then
      echo "❌ Error: Missing CHANGELOG.md in $PKG_NAME"
      exit 1
    fi

    # Verify README.md exists
    if [ ! -f "$PKG_DIR/README.md" ]; then
      echo "❌ Error: Missing README.md in $PKG_NAME"
      exit 1
    fi

    echo "  ✓ $PKG_NAME has LICENSE, CHANGELOG.md, and README.md"
  fi
done

echo "✅ Repository structure and integrity validated successfully!"
