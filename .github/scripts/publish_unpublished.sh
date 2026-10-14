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
  creds_dir="${PUB_CACHE:-$HOME/.pub-cache}"
  mkdir -p "$creds_dir"
  printf '%s' "$PUB_CREDENTIALS" > "$creds_dir/credentials.json"
fi

for dir in "${ordered[@]}"; do
  name="$(field name "$dir")"
  tag="$name-v$(field version "$dir")"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] would publish $dir and tag $tag"
    continue
  fi
  echo "==> Publishing $dir"
  (cd "$dir" && dart pub publish --force)
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "Tag $tag already exists; skipping."
  else
    git tag "$tag"
    git push origin "$tag"
  fi
done
