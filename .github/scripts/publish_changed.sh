#!/usr/bin/env bash
# Publishes every package whose `version:` changed between BASE_SHA and HEAD,
# then tags it as <package>-v<version>. Federated plugins are published in
# dependency order: platform interfaces, platform implementations, app-facing.
#
# Environment:
#   BASE_SHA          Ref to diff against (default: HEAD~1).
#   DRY_RUN=1         Print what would be published without publishing/tagging.
#   PUB_CREDENTIALS   pub.dev credentials JSON (required unless DRY_RUN=1).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
base="${BASE_SHA:-HEAD~1}"

version_at() {
  git show "$1:$2/pubspec.yaml" 2>/dev/null | sed -n 's/^version:[[:space:]]*//p' | head -n1 | tr -d "\"' " || true
}

changed=()
while IFS= read -r pubspec; do
  dir="$(dirname "$pubspec")"
  if grep -q '^publish_to:[[:space:]]*none' "$pubspec"; then continue; fi
  old="$(version_at "$base" "$dir")"
  new="$(version_at HEAD "$dir")"
  if [ -n "$new" ] && [ "$old" != "$new" ]; then
    changed+=("$dir")
  fi
done < <(find packages -name pubspec.yaml -not -path '*/example/*' | sort)

if [ "${#changed[@]}" -eq 0 ]; then
  echo "No package versions changed since $base; nothing to publish."
  exit 0
fi

stage() {
  local dir name parent
  dir="$1"; name="$(basename "$dir")"; parent="$(basename "$(dirname "$dir")")"
  if [[ "$name" == *_platform_interface ]]; then echo 1
  elif [ "$name" != "$parent" ] && [ "$parent" != "packages" ]; then echo 2
  else echo 3
  fi
}

ordered=()
for s in 1 2 3; do
  for dir in "${changed[@]}"; do
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
  name="$(sed -n 's/^name:[[:space:]]*//p' "$dir/pubspec.yaml" | head -n1)"
  tag="$name-v$(version_at HEAD "$dir")"
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
