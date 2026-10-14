#!/usr/bin/env bash
# The validate pipeline as one script, so CI and a local run execute exactly the
# same commands.
#
#   .github/scripts/ci.sh <step>      run one step in this checkout
#   .github/scripts/ci.sh all         run every step in this checkout
#   .github/scripts/ci.sh local       run every step on a fresh clone of the
#                                     committed HEAD (what CI will see), so
#                                     uncommitted or untracked files cannot hide
#                                     a failure. Run this before every push.
#
# Steps: pub-get format analyze scripts workflows tests publish-check
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

step_pub_get() { flutter pub get; }
step_format() { dart format --output=none --set-exit-if-changed .; }
step_analyze() { dart analyze --fatal-infos; }

step_scripts() { .github/scripts/test/publish_unpublished_test.sh; }

step_workflows() {
  # Explicit files, not a directory: the runner's Node rejects a directory.
  node --test .github/scripts/test/*.test.js
  if command -v actionlint >/dev/null 2>&1; then
    actionlint
  else
    echo "actionlint not installed; skipping workflow lint (CI does not run it)"
  fi
}

step_tests() { .github/scripts/run_tests.sh; }

step_publish_check() {
  local pubspec dir
  while IFS= read -r pubspec; do
    dir="$(dirname "$pubspec")"
    echo "==> $dir"
    (cd "$dir" && dart pub publish --dry-run)
  done < <(find packages -name pubspec.yaml -not -path '*/example/*' | sort)
}

run_all() {
  local failed=()
  local s
  for s in pub-get format analyze scripts workflows tests publish-check; do
    echo
    echo "################ $s ################"
    if ! "step_${s//-/_}"; then failed+=("$s"); fi
  done
  if [ "${#failed[@]}" -gt 0 ]; then
    printf '\nFAILED steps: %s\n' "${failed[*]}"
    return 1
  fi
  printf '\nAll validate steps passed.\n'
}

case "${1:-}" in
  pub-get|format|analyze|scripts|workflows|tests|publish-check)
    "step_${1//-/_}"
    ;;
  all)
    run_all
    ;;
  local)
    if [ -n "$(git status --porcelain)" ]; then
      echo "Note: uncommitted changes are NOT included; only the committed HEAD is tested."
    fi
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    git clone --quiet --no-hardlinks "$root" "$tmp/repo"
    cd "$tmp/repo"
    run_all
    ;;
  *)
    echo "usage: $0 {pub-get|format|analyze|scripts|workflows|tests|publish-check|all|local}" >&2
    exit 64
    ;;
esac
