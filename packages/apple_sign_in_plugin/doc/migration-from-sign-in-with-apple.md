# Migration Guide: `package:sign_in_with_apple` → `package:apple_sign_in_plugin`

This guide explains how to migrate existing Flutter code from `sign_in_with_apple` (AboutYou) to the official first-party, cross-platform `apple_sign_in_plugin`.

---

## 1. Pubspec Dependency Update

### Old (`pubspec.yaml`):
```yaml
dependencies:
  sign_in_with_apple: ^6.1.4
```

### New (`pubspec.yaml`):
```yaml
dependencies:
  apple_sign_in_plugin: ^2.1.0
```

---

## 2. API Mapping Cheat Sheet

| Operation | Old (`sign_in_with_apple`) | New (`apple_sign_in_plugin`) |
| :--- | :--- | :--- |
| **Check Availability** | `SignInWithApple.isAvailable()` | `AppleSignIn.instance.isAvailable()` |
| **Sign In** | `SignInWithApple.getAppleIDCredential(...)` | `AppleSignIn.instance.signIn(...)` |
| **Local Sign Out** | *(Not supported)* | `AppleSignIn.instance.signOut()` |
| **Credential State** | `SignInWithApple.getCredentialState(...)` | `AppleSignIn.instance.getCredentialState(...)` |
| **Revocation Events** | *(Not supported)* | `AppleSignIn.instance.onCredentialRevoked` |
| **Disconnect** | *(Not supported)* | `AppleSignIn.instance.disconnect(...)` |
| **Capabilities** | *(Not supported)* | `AppleSignIn.instance.capabilities()` |
| **Diagnostics** | *(Not supported)* | `AppleSignIn.instance.diagnostics()` |

---

## 3. Code Migration Example

### Before:
```dart
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

final credential = await SignInWithApple.getAppleIDCredential(
  scopes: [
    AppleIDAuthorizationScopes.email,
    AppleIDAuthorizationScopes.fullName,
  ],
);
print(credential.userIdentifier);
```

### After:
```dart
import 'package:apple_sign_in_plugin/apple_sign_in_plugin.dart';

final credential = await AppleSignIn.instance.signIn(
  scopes: {
    AppleAuthorizationScope.email,
    AppleAuthorizationScope.fullName,
  },
);
print(credential.userIdentifier);
print('Is first authorization: ${credential.isFirstAuthorization}');
```
