# apple_sign_in_plugin_darwin

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

The iOS and macOS implementation of
[`apple_sign_in_plugin`](https://pub.dev/packages/apple_sign_in_plugin).

This package uses Apple's `AuthenticationServices` framework directly
(`ASAuthorizationAppleIDProvider` / `ASAuthorizationController`) — no
third-party Apple Sign-In SDK is used or depended on. Native code is shared
between iOS and macOS (`sharedDarwinSource`); see `darwin/`.

## Usage

This package is endorsed, meaning you can simply use `apple_sign_in_plugin`
normally. This package will be automatically included in your app when you
depend on `apple_sign_in_plugin`, so you likely do not need to add
it to your own `pubspec.yaml`.

## Backend Boundary

This package only talks to Apple's on-device `AuthenticationServices`
framework — it never contacts a server. The identity token and
authorization code it returns must still be verified server-side before
you trust them for anything security-sensitive. See
[`apple_sign_in_plugin_platform_interface`'s "Backend Boundary" section](https://pub.dev/packages/apple_sign_in_plugin_platform_interface#backend-boundary)
for details, and the top-level
[`apple_sign_in_plugin` README's "Do I Need a Backend?"](https://pub.dev/packages/apple_sign_in_plugin#-do-i-need-a-backend)
section for backend recipes (PHP, Laravel, Node.js, Express, NestJS).

## 👤 Author

Maintained by **DHC Tech**.

## 📄 License

This package is licensed under the **[MIT License](LICENSE)**.
