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

## 👤 Author

Maintained by **DHC Tech**.

## 📄 License

This package is licensed under the **[MIT License](LICENSE)**.
