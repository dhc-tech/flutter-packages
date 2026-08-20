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
* New: `configure` and the generic `build` command now automatically run
  `icons_launcher:create` and `flutter_native_splash:create` for a tenant
  if that tenant already has its own `icons_launcher-<id>.yaml` /
  `flutter_native_splash-<id>.yaml` config file — no more remembering to
  run those two commands (plus a host app's own
  `tool/register_launch_screen.rb`, run automatically too when present)
  by hand every time. Neither package is a dependency of this one, and
  neither is required: a tenant with no such config file for one or both
  is silently skipped, never forced into a dependency it doesn't use. See
  the new `generateIconsAndSplash` export
  (`lib/src/generation/icon_splash_generator.dart`).

## 0.0.3

* Initial release into the `flutter-packages` monorepo.
