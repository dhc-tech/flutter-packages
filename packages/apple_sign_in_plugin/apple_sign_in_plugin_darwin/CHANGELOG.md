## 0.0.1-dev.2

* Fixed the dependency constraint on `apple_sign_in_plugin_platform_interface`
  (was `^0.0.1`, which doesn't match any published version and broke
  `pub get`/`pana` resolution — the root cause of this package's 0 pub
  points on dependency, platform-support, static-analysis, and
  documentation checks). Now `^0.0.1-dev.1`.
* Added a real "Backend Boundary" section to the README, and made the
  dartdoc/example references to it clickable links instead of dead text.

## 0.0.1-dev.1

* No functional change. Republish after the dev.0 release order (app-facing package failing before its platform dependencies were live on pub.dev).

## 0.0.1-dev.0

* Initial release. Extracted from `apple_sign_in_plugin` as the iOS/macOS platform implementation package, as part of federating the package into app-facing, platform-interface, and platform-implementation packages.