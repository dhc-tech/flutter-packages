## 2.0.0-dev.1

* Trimmed `pubspec.yaml` topics to 5 (pub.dev's maximum); the previous
  9-topic list blocked publishing entirely.

## 2.0.0-dev.0

* **BREAKING**: Complete rewrite. Removed the dependency on the
  third-party `sign_in_with_apple` package — every platform is now
  implemented natively/directly against Apple's own mechanisms, with no
  third-party Apple Sign-In SDK anywhere in the dependency graph.
* **BREAKING**: Removed `AppleSignInPlugin.initialize()`,
  `.signInWithApple()`, `.signOut()`, `.isSignedIn()`, and the
  `AppleSignInResult` class. Replaced with the `AppleSignIn.instance`
  API: `.signIn()`, `.signOut()`, `.disconnect()`, `.getCredentialState()`,
  `.events`, `.capabilities()`, `.diagnostics()`, and a new strongly-typed
  `AppleAuthSession` model (`identity`, `authentication`, `authorization`,
  `lifecycle`, `metadata`).
* **BREAKING**: Removed client-side token exchange, token revocation, and
  local session storage. A previous version of this package bundled an
  Apple private key (`.pem`) inside the compiled app to perform this
  client-side — a real security issue. Token exchange and true
  revocation are now documented as backend responsibilities, with
  ready-made backend recipes — see the README's "Do I Need a Backend?"
  section.
* **BREAKING**: Federated the package. Platform implementations now live
  in their own packages — `apple_sign_in_plugin_darwin` (iOS/macOS),
  `apple_sign_in_plugin_android`, `apple_sign_in_plugin_web`,
  `apple_sign_in_plugin_windows`, `apple_sign_in_plugin_linux` — behind
  the shared `apple_sign_in_plugin_platform_interface` contract.
  `apple_sign_in_plugin` itself is now a pure-Dart, app-facing package.
  No action is needed for apps that only ever imported
  `package:apple_sign_in_plugin/apple_sign_in_plugin.dart` and used the
  new `AppleSignIn.instance` API.
* Added real implementations for Android (Custom Tabs), Web (Sign in
  with Apple JS, including WasmGC), Windows, and Linux (system-browser
  OAuth flow) — every platform this package advertises now has a working
  implementation, not a stub.
* Added `AppleCredentialState`/`getCredentialState()`,
  `AppleRealUserStatus`, and native credential-revocation events
  (surfaced through `AppleSignIn.instance.events`) on iOS/macOS.

**Note:** this is a pre-release (`-dev`) version for internal testing —
it has not been promoted to a stable release yet.

## 1.2.6

* Last version published to pub.dev before this rewrite.
