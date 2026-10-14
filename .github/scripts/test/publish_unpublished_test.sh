#!/usr/bin/env bash
# Tests publish_unpublished.sh in dry-run mode against a local fake pub.dev API.
# Usage: .github/scripts/test/publish_unpublished_test.sh
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"
script=".github/scripts/publish_unpublished.sh"

work="$(mktemp -d)"
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

field() { sed -n "s/^$1:[[:space:]]*//p" "$2/pubspec.yaml" | head -n1 | tr -d "\"' "; }

# Publish every package version into the fake API (a file per version = HTTP 200).
publish() { mkdir -p "$work/api/packages/$1/versions"; echo '{}' > "$work/api/packages/$1/versions/$2"; }
unpublish() { rm -f "$work/api/packages/$1/versions/$2"; }

packages=()
while IFS= read -r pubspec; do packages+=("$(dirname "$pubspec")"); done \
  < <(find packages -name pubspec.yaml -not -path '*/example/*' | sort)
for dir in "${packages[@]}"; do publish "$(field name "$dir")" "$(field version "$dir")"; done

port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$work/api" >/dev/null 2>&1 &
server_pid=$!
for _ in $(seq 1 50); do
  curl -s -o /dev/null "http://127.0.0.1:$port/" && break
  sleep 0.1
done

failures=0
check() {
  local name="$1" condition="$2"
  if eval "$condition"; then echo "ok   - $name"; else echo "FAIL - $name"; failures=$((failures + 1)); fi
}
run() { DRY_RUN=1 PUB_API="http://127.0.0.1:$port" "$script" 2>&1; }

# 1. Everything published: nothing to do.
out="$(run)"
check "nothing to publish when every version is on pub.dev" '[[ "$out" == *"nothing to publish"* ]]'
check "no package is reported as publishable" '! grep -q "would publish" <<<"$out"'

# 2. Three unpublished packages are reported, in dependency order.
iface_dir=packages/apple_sign_in_plugin/apple_sign_in_plugin_platform_interface
impl_dir=packages/apple_sign_in_plugin/apple_sign_in_plugin_android
app_dir=packages/apple_sign_in_plugin/apple_sign_in_plugin
for dir in "$app_dir" "$impl_dir" "$iface_dir"; do unpublish "$(field name "$dir")" "$(field version "$dir")"; done
out="$(run)"
check "exactly the three unpublished packages are listed" '[ "$(grep -c "would publish" <<<"$out")" -eq 3 ]'
iface_line="$(grep -n "$iface_dir " <<<"$out" | cut -d: -f1)"
impl_line="$(grep -n "$impl_dir " <<<"$out" | cut -d: -f1)"
app_line="$(grep -n "$app_dir " <<<"$out" | cut -d: -f1)"
check "platform interface is published before implementations" '[ "$iface_line" -lt "$impl_line" ]'
check "implementations are published before the app-facing package" '[ "$impl_line" -lt "$app_line" ]'
check "tags use <package>-v<version>" 'grep -q "tag apple_sign_in_plugin_android-v$(field version "$impl_dir")" <<<"$out"'

# 3. An unreachable API must fail loudly instead of publishing blindly.
if DRY_RUN=1 PUB_API="http://127.0.0.1:1" "$script" >/dev/null 2>&1; then rc=0; else rc=$?; fi
check "an unreachable pub API fails the run" '[ "$rc" -ne 0 ]'

# 4. A real (non dry-run) publish refuses to start without credentials.
if env -u PUB_CREDENTIALS PUB_API="http://127.0.0.1:$port" "$script" >/dev/null 2>&1; then rc=0; else rc=$?; fi
check "publishing without PUB_CREDENTIALS fails" '[ "$rc" -ne 0 ]'

[ "$failures" -eq 0 ] || { echo "$failures check(s) failed"; exit 1; }
echo "all checks passed"
