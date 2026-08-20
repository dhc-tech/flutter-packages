## 0.0.4

* `generateIosConfig` now also sets `APP_DISPLAY_NAME` (from
  `TenantConfig.ios.appName`) on the project root object and the `Runner`
  target's `Debug-<tenant>`/`Release-<tenant>`/`Profile-<tenant>` build
  configurations — previously only `PRODUCT_BUNDLE_IDENTIFIER` was set. A
  stock `flutter create` project's `Info.plist` already reads
  `CFBundleDisplayName`/`CFBundleName` from `$(APP_DISPLAY_NAME)`, so
  without this a tenant build's home-screen name silently fell back to
  "Runner" instead of the tenant's real brand name.
* Fixed `removeIosConfig` leaving orphaned `XCBuildConfiguration` objects
  in `project.pbxproj` after removing a tenant — the build configurations
  were unlinked from every target's `build_configuration_list` but never
  actually removed from the project's object table, so a
  remove/re-add cycle for the same tenant id accumulated dead objects over
  time.
* New: `configure` and the generic `build` command now automatically
  generate launcher **and notification** icons via `icons_launcher`, fully
  derived from a tenant's own `assets.icon` (or `assets.logo`) already
  declared in `white_label.yaml` — no separate `icons_launcher-<id>.yaml`
  to hand-author, and `icons_launcher` itself is now a real dependency of
  this package, so it's resolved for a consuming app automatically too
  (nothing to add to the host app's own `pubspec.yaml`). See the new
  `generateLauncherIcon` export (`lib/src/generation/launcher_icon_generator.dart`);
  `generateIosConfig` sets `ASSETCATALOG_COMPILER_APPICON_NAME` to match
  the `<tenant>AppIcon` catalog it creates.
* New: `configure` and the generic `build` command also automatically
  generate the native splash screen via `flutter_native_splash`, fully
  derived from `assets.splash` (falling back to `assets.icon`/`logo`) and
  the new `theme.splash_color` (falling back to `theme.primary_color`,
  then white) — no separate `flutter_native_splash-<id>.yaml` to
  hand-author either, and `flutter_native_splash` is likewise now a real
  dependency of this package. `theme.splash_color` exists as its own field
  because a brand's `primary_color` is often too vivid for a full-screen
  splash background — assuming it's always splash-appropriate is a real
  bug this avoids by construction. A host app's own
  `tool/register_launch_screen.rb` (if present) is run automatically too.
  See the new `generateNativeSplash` export
  (`lib/src/generation/icon_splash_generator.dart`) and
  `TenantTheme.splashColor`.
* New: both the icon and splash generators now merge a tenant's raw
  `icons_launcher:`/`native_splash:` block (if declared in
  `white_label.yaml`) over their own auto-derived defaults — nested maps
  merge rather than replace wholesale, so declaring one option doesn't
  drop the others. Every option either underlying package supports
  (adaptive icon background/foreground, dark-mode colors, `fullscreen`,
  per-platform overrides, …) is reachable straight from `white_label.yaml`
  this way, without this package needing to model each one individually.
* Both icon and splash generation can be disabled per tenant with
  `features: { launcher_icon: false }` / `features: { native_splash:
  false }` in `white_label.yaml` — for a tenant that already has its own
  hand-crafted setup and wants this package to leave it alone.
* Fixed: `README.md` had been accidentally overwritten with an unrelated
  host app's README in a prior commit (`chore: dart format and local
  working tree changes (#36)`) — restored, and its "Add Dev Dependency"
  section corrected to `dependencies` (not `dev_dependencies`): the
  generated `lib/white_label.g.dart` imports this package's runtime types
  and is compiled into the shipped app, so it's a real runtime dependency,
  not a build-time-only tool.

## 0.0.3

* Initial release into the `flutter-packages` monorepo.
