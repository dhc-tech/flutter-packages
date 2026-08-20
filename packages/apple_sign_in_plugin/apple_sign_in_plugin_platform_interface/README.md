# apple_sign_in_plugin_platform_interface

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A common platform interface for the
[`apple_sign_in_plugin`](https://pub.dev/packages/apple_sign_in_plugin)
package.

This package defines the interface that platform-specific implementations
of `apple_sign_in_plugin` must implement to be registered as the platform's
`AppleSignInPlatform`, plus:

- The shared, strongly-typed models: `AppleCredential`, `ApplePersonName`,
  `AppleAuthorizationScope`, `AppleCredentialState`, `AppleRealUserStatus`,
  `AppleSignInException`, `AppleAuthSession` (and its `AppleAuthIdentity` /
  `AppleAuthTokens` / `AppleAuthAuthorization` / `AppleAuthLifecycle` /
  `AppleAuthMetadata` components), `AppleAuthEvent`,
  `AppleSignInCapabilities`, `AppleSignInDiagnostics`,
  `AppleDisconnectResult`, and the `AppleBackendAdapter` interface.
- A default `MethodChannel`-based implementation
  (`MethodChannelAppleSignIn`) that platform packages can reuse when their
  Dart-side logic doesn't need to differ from the channel contract.
- A `JwtDecoder` utility for inspecting (not verifying) JWT contents —
  used internally as a best-effort fallback to populate
  `AppleAuthIdentity.email` when a platform's native response doesn't
  include it directly.

## Usage

App developers should generally not need to depend on this package
directly — depend on
[`apple_sign_in_plugin`](https://pub.dev/packages/apple_sign_in_plugin)
instead.

Platform implementation authors should implement `AppleSignInPlatform`
(extend, not implement, so new methods added here don't break existing
implementations at compile time) and register it as
`AppleSignInPlatform.instance` from their own package's `registerWith()`.

## Backend Boundary

Everything in this package runs entirely on-device. In particular,
[`JwtDecoder`](lib/src/jwt_decoder.dart) only *reads* the claims inside an
Apple identity token (JWT) — it never checks the token's cryptographic
signature. That decoded output (and the `email` it feeds into
`AppleAuthIdentity.email` as a fallback) must be treated as **untrusted**
until a server you control has verified it.

- ❌ **Do not** use `JwtDecoder` output, or `AppleCredential`/`AppleAuthSession`
  fields derived from it, as proof of identity for anything security-sensitive.
- ✅ **Do** send the credential's `identityToken` and `authorizationCode` to
  your backend, and verify the token there against Apple's public keys
  (`https://appleid.apple.com/auth/keys`) before trusting any claim in it.
- The `AppleBackendAdapter` interface in this package exists specifically
  to model that boundary: platform packages call into it for operations
  (like true token revocation) that Apple only allows a server to perform.

See the top-level
[`apple_sign_in_plugin` README's "Do I Need a Backend?"](https://pub.dev/packages/apple_sign_in_plugin#do-i-need-a-backend)
section for the full picture, including backend recipes for PHP, Laravel,
Node.js, Express, and NestJS.

## 👤 Author

Maintained by **DHC Tech**.

## 📄 License

This package is licensed under the **[MIT License](LICENSE)**.
