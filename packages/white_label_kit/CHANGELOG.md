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
* New: `configure` and the generic `build` command also automatically run
  `flutter_native_splash:create` for a tenant if it already has its own
  `flutter_native_splash-<id>.yaml` config file (plus a host app's own
  `tool/register_launch_screen.rb`, run automatically too when present) —
  `flutter_native_splash` is likewise now a real dependency of this
  package. Splash still needs its own config file (unlike the icon, it
  can't be safely auto-derived without a declared background color); a
  tenant with none is silently skipped, never forced into using it. See
  the new `generateNativeSplash` export
  (`lib/src/generation/icon_splash_generator.dart`).

## 0.0.3

* Initial release into the `flutter-packages` monorepo.
