#!/usr/bin/env bash
# Copyright 2026 DHC Tech
# Use of this source code is governed by an MIT-style license that can be
# found in the LICENSE file.
# Runs automated unit and widget test suites across all packages.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "🧪 Running automated test matrix across all packages..."
for PKG_DIR in "$REPO_ROOT"/packages/*; do
  if [ -d "$PKG_DIR/test" ]; then
    PKG_NAME=$(basename "$PKG_DIR")
    echo "  -> Testing $PKG_NAME..."
    (
      cd "$PKG_DIR"
      if grep -q "sdk: flutter" pubspec.yaml; then
        flutter test
      else
        dart test
      fi
    )
  fi
done

echo "✅ All test suites passed successfully!"
