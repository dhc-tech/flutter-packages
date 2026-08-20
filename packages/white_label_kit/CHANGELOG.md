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
* New, opt-in: `configure` and the generic `build` command can now
  auto-generate a tenant's launcher/notification icon
  (`icons_launcher-<id>.yaml`) and native splash screen
  (`flutter_native_splash-<id>.yaml`) — declare `features: {
  icon_generate: true }` / `{ splash_generate: true }` for a tenant and
  either config file is auto-created (from `assets.icon`/`assets.logo`,
  or `assets.splash`/`assets.icon`/`assets.logo` + `theme.primary_color`)
  **only if it doesn't already exist** — a hand-authored file is never
  touched. Off by default: a tenant that declares neither flag sees no
  change in behavior. `icons_launcher` is a real `dependency` of this
  package (it's pure Dart, no Flutter SDK needed to resolve), so `dart run
  icons_launcher:create` resolves for a consuming app with nothing added
  to its own `pubspec.yaml`. `flutter_native_splash` **cannot** be a
  dependency of this package the same way — it requires the Flutter SDK
  to resolve, which broke `dart pub publish` for this package entirely
  when tried (real CI failure, caught before release) — so a consuming
  app must add `flutter_native_splash` to its own `pubspec.yaml` for
  splash generation to work; icon generation needs no such step. See the
  new `maybeGenerateLauncherIcon`/`maybeGenerateNativeSplash` exports
  (`lib/src/generation/icon_splash_generator.dart`).

## 0.0.3

* Initial release into the `flutter-packages` monorepo.
