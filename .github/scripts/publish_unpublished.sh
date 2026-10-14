#!/usr/bin/env bash
# Publishes every package whose current `version:` is not on pub.dev yet, then
# tags it as <package>-v<version>. Federated plugins are published in
# dependency order: platform interfaces, platform implementations, app-facing.
#
# Because it compares against pub.dev rather than a git diff, it is idempotent
# and self-healing: it can run on every push, on a schedule, or by hand, and a
# run that was skipped or failed halfway is simply completed by the next one.
#
# Environment:
#   DRY_RUN=1         Print what would be published without publishing/tagging.
#   PUB_CREDENTIALS   pub.dev credentials JSON (required unless DRY_RUN=1).
#   PUB_API           Base URL of the pub API (default: https://pub.dev/api).
#   PUBLISH_TIMEOUT   Seconds to allow one `dart pub publish` (default: 600). A
#                     publish that needs a pub.dev login would otherwise wait
#                     forever for a browser, so it fails instead.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
pub_api="${PUB_API:-https://pub.dev/api}"

field() {
  sed -n "s/^$1:[[:space:]]*//p" "$2/pubspec.yaml" | head -n1 | tr -d "\"' "
}

is_published() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "$pub_api/packages/$1/versions/$2")"
  case "$code" in
    200) return 0 ;;
    404) return 1 ;;
    *) echo "Unexpected HTTP $code from pub.dev for $1 $2" >&2; exit 1 ;;
  esac
}

stage() {
  local name parent
  name="$(basename "$1")"; parent="$(basename "$(dirname "$1")")"
  if [[ "$name" == *_platform_interface ]]; then echo 1
  elif [ "$name" != "$parent" ] && [ "$parent" != "packages" ]; then echo 2
  else echo 3
  fi
}

pending=()
while IFS= read -r pubspec; do
  dir="$(dirname "$pubspec")"
  if grep -q '^publish_to:[[:space:]]*none' "$pubspec"; then continue; fi
  name="$(field name "$dir")"
  version="$(field version "$dir")"
  if ! is_published "$name" "$version"; then
    pending+=("$dir")
  fi
done < <(find packages -name pubspec.yaml -not -path '*/example/*' | sort)

if [ "${#pending[@]}" -eq 0 ]; then
  echo "Every package version is already on pub.dev; nothing to publish."
  exit 0
fi

ordered=()
for s in 1 2 3; do
  for dir in "${pending[@]}"; do
    [ "$(stage "$dir")" = "$s" ] && ordered+=("$dir")
  done
done

if [ "${DRY_RUN:-0}" != "1" ]; then
  : "${PUB_CREDENTIALS:?PUB_CREDENTIALS is required to publish}"
  # `dart pub` reads its credentials from the user config directory
  # (~/.config/dart on Linux, ~/Library/Application Support/dart on macOS) and
  # from the legacy $PUB_CACHE/credentials.json; write every place it may look.
  case "$(uname -s)" in
    Darwin) config_dir="$HOME/Library/Application Support/dart" ;;
    *) config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/dart" ;;
  esac
  cache_dir="${PUB_CACHE:-$HOME/.pub-cache}"
  mkdir -p "$config_dir" "$cache_dir"
  printf '%s' "$PUB_CREDENTIALS" > "$config_dir/pub-credentials.json"
  printf '%s' "$PUB_CREDENTIALS" > "$cache_dir/credentials.json"
fi

publish() {
  local limit="${PUBLISH_TIMEOUT:-600}" rc=0 pid watchdog
  dart pub publish --force </dev/null &
  pid=$!
  # Portable watchdog (no GNU `timeout` on macOS): kill the publish if it is
  # still running after $limit seconds.
  # Detached from stdout/stderr so its sleep cannot hold a caller's pipe open.
  (sleep "$limit"; kill "$pid" 2>/dev/null) >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid" || rc=$?
  if kill -0 "$watchdog" 2>/dev/null; then
    pkill -P "$watchdog" 2>/dev/null || true
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
  else
    echo "dart pub publish timed out after ${limit}s; it is probably waiting for a pub.dev login. Check that PUB_CREDENTIALS is valid and not expired." >&2
    [ "$rc" -ne 0 ] || rc=1
  fi
  return "$rc"
}

for dir in "${ordered[@]}"; do
  name="$(field name "$dir")"
  tag="$name-v$(field version "$dir")"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would publish $dir and tag $tag"
    continue
  fi
  echo "==> Publishing $dir"
  (cd "$dir" && publish)
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "Tag $tag already exists; skipping."
  else
    git tag "$tag"
    git push origin "$tag"
  fi
done
