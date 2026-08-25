## 0.0.6

* New: Full Monorepo & Melos workspace support via `--project-root`,
  `--config`, and `--ide-root` CLI flags across `configure`, `generate`,
  `build`, `run`, `doctor`, `validate`, `list`, `add-tenant`, and
  `remove-tenant`.
* Supports nested Flutter apps (e.g. `apps/<flutter-app>`) while placing
  IDE run configurations (`.vscode/launch.json`, `.run/*.xml`) at the
  monorepo root or custom workspace root.

## 0.0.5

* Fixed: generated `.run/*.xml` (Android Studio/IntelliJ run configs) had
  invalid XML and never showed up in the Run menu — a stray
  `.substring(1)` was stripping the leading `<`. See README for details.
* iOS splash storyboards are now auto-registered into Xcode's Resources
  build phase (previously a manual `ruby` step).
* `build --mode release` now always adds `--obfuscate
  --split-debug-info=...` (see [Flutter's obfuscation guide](https://docs.flutter.dev/deployment/obfuscate)).
* Auto-generated `icons_launcher-<id>.yaml` now includes an adaptive icon
  (Android 8+) by default.
* New: named per-tenant `environments:` + `--env` (staging/production/etc.)
  for `generate`/`configure`/`build`/`run`, with an arbitrary `custom:`
  key-value map per environment.
* Fixed: `configure`/`build`/`run` could regenerate `lib/white_label.g.dart`
  for the wrong tenant, or not at all, in some flows — now always for the
  tenant/`--env` actually resolved.
* Fixed: `build.yaml`'s `auto_apply: dependents` could silently delete a
  consumer's own `lib/white_label.g.dart` via `build_runner` — now
  `auto_apply: none` (opt-in).
* `doctor` now flags a missing `flutter_native_splash` dependency ahead of
  time when `splash_generate` is on.
* Removed `auto-onboard`/`autoOnboardTenant` — untested, non-functional
  for any real consumer. Use `add-tenant` + `configure` instead.
* Added `meta` as a direct dependency (for `@visibleForTesting`).

See README for full usage of anything above.

## 0.0.4

* `generateIosConfig` now also sets `APP_DISPLAY_NAME` (previously only
  `PRODUCT_BUNDLE_IDENTIFIER`) — fixes a tenant build's home-screen name
  falling back to "Runner".
* Fixed `removeIosConfig` leaving orphaned `XCBuildConfiguration` objects
  after removing a tenant.
* New, opt-in (`features: { icon_generate: true }` / `{ splash_generate:
  true }`): `configure`/`build` auto-generate a tenant's launcher icon and
  native splash config, only if the file doesn't already exist. See
  README for the `flutter_native_splash` dependency note.

## 0.0.3

* Initial release into the `flutter-packages` monorepo.
