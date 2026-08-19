# apple_sign_in_plugin_windows

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

The Windows implementation of
[`apple_sign_in_plugin`](https://pub.dev/packages/apple_sign_in_plugin).

Windows has no native Apple authentication API, so this package uses
Apple's official "Sign in with Apple for the web" authorization flow via
the system's default browser. No third-party Apple Sign-In SDK is used.

## Usage

This package is endorsed, meaning you can simply use `apple_sign_in_plugin`
normally. This package will be automatically included in your app when you
depend on `apple_sign_in_plugin`, so you likely do not need to add it to
your own `pubspec.yaml`.

Windows requires additional one-time configuration (a Services ID,
redirect URI, and a registered callback scheme) — see the main package's
README for setup instructions.

## 👤 Author

Maintained by **DHC Tech**.

## 📄 License

This package is licensed under the **[MIT License](LICENSE)**.
