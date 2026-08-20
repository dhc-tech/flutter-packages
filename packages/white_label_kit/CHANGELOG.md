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

## 0.0.3

* Initial release into the `flutter-packages` monorepo.
