# apple_sign_in_plugin_web

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

The web implementation of
[`apple_sign_in_plugin`](https://pub.dev/packages/apple_sign_in_plugin).

This package uses Apple's official **Sign in with Apple JS** SDK via JS
interop (compatible with both the JavaScript and WasmGC Flutter web
compile targets). No third-party Apple Sign-In SDK is used.

## Usage

This package is endorsed, meaning you can simply use `apple_sign_in_plugin`
normally. This package will be automatically included in your app when you
depend on `apple_sign_in_plugin`, so you likely do not need to add it to
your own `pubspec.yaml`.

Web requires additional one-time configuration (Apple's JS SDK script
tag in `web/index.html`, plus a Services ID and redirect URI) — see the
main package's README for setup instructions.

## 👤 Author

Maintained by **DHC Tech**.

## 📄 License

This package is licensed under the **[MIT License](LICENSE)**.
