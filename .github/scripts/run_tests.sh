#!/usr/bin/env bash
# Runs the tests of every workspace package that has a test/ directory.
# Usage: .github/scripts/run_tests.sh [package_dir ...]
# With no arguments, every package under packages/ (examples excluded) is tested.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [ "$#" -gt 0 ]; then
  packages=("$@")
else
  packages=()
  while IFS= read -r pubspec; do
    packages+=("$(dirname "$pubspec")")
  done < <(find packages -name pubspec.yaml -not -path '*/example/*' | sort)
fi

failed=()
for pkg in "${packages[@]}"; do
  [ -d "$pkg/test" ] || continue
  echo "==> $pkg"
  if ! grep -q 'sdk: flutter' "$pkg/pubspec.yaml"; then
    cmd=(dart test)
  elif [[ "$pkg" == *_web ]]; then
    # Web implementations depend on dart:js_interop and only load in a browser.
    cmd=(flutter test --platform chrome)
  else
    cmd=(flutter test)
  fi
  (cd "$pkg" && "${cmd[@]}") || failed+=("$pkg")
done

if [ "${#failed[@]}" -gt 0 ]; then
  printf 'Tests failed in:\n'
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
