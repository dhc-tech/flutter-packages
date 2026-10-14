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

# 5. A real publish writes the credentials where `dart pub` reads them, runs
#    `dart pub publish --force` in the package, and tags it. Everything runs in a
#    throwaway clone whose origin is a local bare repo, never the real remote.
git clone --quiet --bare "$root" "$work/origin.git"
git clone --quiet "$work/origin.git" "$work/repo"
mkdir -p "$work/bin" "$work/home"
cat > "$work/bin/dart" <<FAKE
#!/usr/bin/env bash
echo "\$(basename "\$PWD") \$*" >> "$work/dart_calls"
case "\${FAKE_DART_MODE:-ok}" in hang) exec sleep 30 ;; esac
FAKE
chmod +x "$work/bin/dart"

app_dir=packages/dig_cli
for dir in "${packages[@]}"; do publish "$(field name "$dir")" "$(field version "$dir")"; done
unpublish "$(field name "$app_dir")" "$(field version "$app_dir")"
: > "$work/dart_calls"
publish_run() {
  (cd "$work/repo" && env -u XDG_CONFIG_HOME PATH="$work/bin:$PATH" HOME="$work/home" \
    PUB_CACHE="$work/pubcache" PUB_API="http://127.0.0.1:$port" PUB_CREDENTIALS='{"fake":"creds"}' \
    "$@" "$root/$script")
}
out="$(publish_run 2>&1)" && rc=0 || rc=$?
check "a real publish succeeds" '[ "$rc" -eq 0 ]'
check "dart pub publish --force runs in the unpublished package only" '[ "$(cat "$work/dart_calls")" = "dig_cli pub publish --force" ]'
check "credentials are written to the dart config directory" '[ "$(cat "$work/home/.config/dart/pub-credentials.json" 2>/dev/null || cat "$work/home/Library/Application Support/dart/pub-credentials.json")" = "{\"fake\":\"creds\"}" ]'
check "credentials are also written to the legacy pub cache location" '[ "$(cat "$work/pubcache/credentials.json")" = "{\"fake\":\"creds\"}" ]'
check "the release tag is pushed to origin" 'git --git-dir="$work/origin.git" tag | grep -qx "dig_cli-v$(field version "$app_dir")"'

# 6. A publish that waits for a pub.dev login fails fast instead of hanging.
if true; then
  git --git-dir="$work/origin.git" tag -d "dig_cli-v$(field version "$app_dir")" >/dev/null
  git -C "$work/repo" tag -d "dig_cli-v$(field version "$app_dir")" >/dev/null
  start=$SECONDS
  out="$(publish_run FAKE_DART_MODE=hang PUBLISH_TIMEOUT=2 2>&1)" && rc=0 || rc=$?
  check "a publish stuck on login fails within the timeout" '[ "$rc" -ne 0 ] && [ $((SECONDS - start)) -lt 20 ]'
  check "the timeout error mentions the credentials" 'grep -q "PUB_CREDENTIALS" <<<"$out"'
  check "nothing is tagged after a failed publish" '! git --git-dir="$work/origin.git" tag | grep -qx "dig_cli-v$(field version "$app_dir")"'
fi

[ "$failures" -eq 0 ] || { echo "$failures check(s) failed"; exit 1; }
echo "all checks passed"
