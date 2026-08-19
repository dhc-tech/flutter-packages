# apple_sign_in_plugin

[![pub package](https://img.shields.io/pub/v/apple_sign_in_plugin.svg)](https://pub.dev/packages/apple_sign_in_plugin)
[![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B.svg)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Monorepo](https://img.shields.io/badge/monorepo-dhc--tech%2Fflutter--packages-blue.svg)](https://github.com/dhc-tech/flutter-packages)

A comprehensive, production-ready Flutter plugin for integrating **Sign in with Apple** across iOS, macOS, Android, and Web. Handles the full authentication lifecycle, including JWT token decoding, server-side validation payloads, and persistent session state.

---

## ✨ Features

- 🔐 **Native & Web Apple Sign-In**: Native UI on iOS/macOS and OAuth flow for Android and Web.
- 📦 **Backend Verification Ready**: Provides `idToken` (JWT), `accessToken`, `refreshToken`, and authorization codes.
- 👤 **User Identity Extraction**: Decodes user name, email address, and unique user identifier.
- 🔄 **Session State**: Built-in state checking and token management.
- 🛡️ **Cross-Platform**: iOS, macOS, Android, and Web support.

---

## 📱 Platform Support

| Platform | Supported | Implementation |
|---|---|---|
| **iOS** | ✅ | Native `AuthenticationServices` framework |
| **macOS** | ✅ | Native `AuthenticationServices` framework |
| **Android** | ✅ | Apple OAuth via Custom Tabs / Web Flow |
| **Web** | ✅ | Apple JS SDK |

---

## 📦 Installation

Add `apple_sign_in_plugin` to your `pubspec.yaml`:

```yaml
dependencies:
  apple_sign_in_plugin: ^1.2.6
```

Then install dependencies:

```bash
flutter pub get
```

---

## ⚙️ Platform Configuration

### 1. Apple Developer Setup
1. Enable **Sign in with Apple** capability in your Apple Developer Account under **Identifiers** → **App IDs**.
2. For Android / Web support, create a **Service ID**, configure your primary App ID, and set valid redirect URLs.
3. Download your private key (`.p8`) and place your `.pem` key in your project's assets folder if performing direct client-side validation.

### 2. iOS & macOS Configuration
1. Open your project in Xcode (`ios/Runner.xcworkspace` or `macos/Runner.xcworkspace`).
2. Navigate to **Signing & Capabilities**.
3. Click **+ Capability** and select **Sign in with Apple**.

---

## 🚀 Usage

### 1. Initialize Plugin
Initialize the plugin early in your application lifecycle (e.g., in `main.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:apple_sign_in_plugin/apple_sign_in_plugin.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppleSignInPlugin.initialize(
    pemKeyPath: 'assets/keys/apple_private_key.pem',
    keyId: 'YOUR_KEY_ID',
    teamId: 'YOUR_TEAM_ID',
    bundleId: 'com.example.app', // Or your Service ID
  );

  runApp(const MyApp());
}
```

### 2. Trigger Sign In
```dart
Future<void> handleAppleSignIn() async {
  try {
    final result = await AppleSignInPlugin.signInWithApple();

    if (result != null) {
      debugPrint('User ID: ${result.userIdentifier}');
      debugPrint('Email: ${result.email}');
      debugPrint('ID Token (JWT): ${result.idToken}');
      // Send result.idToken to your backend for verification
    } else {
      debugPrint('Apple Sign-In was cancelled by user');
    }
  } catch (error) {
    debugPrint('Apple Sign-In failed: $error');
  }
}
```

### 3. Sign Out
```dart
await AppleSignInPlugin.signOut();
```

### 4. Check Authentication State
```dart
bool signedIn = AppleSignInPlugin.isSignedIn();
```

---

## 📊 Result Data Model (`AppleSignInResult`)

| Property | Type | Description |
|---|---|---|
| `userIdentifier` | `String` | Unique, stable identifier for the user |
| `email` | `String?` | User's verified email address (shared on first sign-in) |
| `givenName` | `String?` | First name (shared on first sign-in) |
| `familyName` | `String?` | Last name (shared on first sign-in) |
| `idToken` | `String?` | JSON Web Token (JWT) proving identity to backend servers |
| `authorizationCode` | `String?` | One-time code for exchanging access/refresh tokens |
| `accessToken` | `String?` | Apple API access token |
| `refreshToken` | `String?` | Refresh token for long-term session maintenance |

---

## 🤝 Contributing & Issues

`apple_sign_in_plugin` is part of the **[dhc-tech/flutter-packages](https://github.com/dhc-tech/flutter-packages)** monorepo.

Contributions and issue reports are welcome at [GitHub Issues](https://github.com/dhc-tech/flutter-packages/issues).

---

## 📄 License

This plugin is licensed under the **[MIT License](LICENSE)**.
