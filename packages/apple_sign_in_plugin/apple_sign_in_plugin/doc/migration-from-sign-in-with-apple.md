# Migrating from `sign_in_with_apple`

## API mapping

| `sign_in_with_apple` | `apple_sign_in_plugin` |
|---|---|
| `SignInWithApple.getAppleIDCredential(scopes: [...])` | `AppleSignIn.instance.signIn(scopes: {...})` |
| `AuthorizationCredentialAppleID` | `AppleAuthSession` (`.identity`, `.authentication`, `.authorization`, `.lifecycle`, `.metadata`) |
| `credential.userIdentifier` | `session.identity.userIdentifier` |
| `credential.email` | `session.identity.email` |
| `credential.givenName` / `.familyName` | `session.identity.name.givenName` / `.familyName` |
| `credential.identityToken` | `session.authentication.identityToken` |
| `credential.authorizationCode` | `session.authentication.authorizationCode` |
| `credential.state` | `session.authentication.state` |
| `SignInWithApple.getCredentialState(userIdentifier)` | `AppleSignIn.instance.getCredentialState(userIdentifier)` |
| `CredentialState` enum | `AppleCredentialState` enum |
| `SignInWithAppleAuthorizationException` | `AppleSignInException` (`.code` is an `AppleSignInErrorCode`) |
| `AuthorizationErrorCode.canceled` | `AppleSignInErrorCode.canceled` |
| — (no equivalent) | `AppleSignIn.instance.events` (unified sign-in/sign-out/revocation/transfer stream) |
| — (no equivalent) | `AppleSignIn.instance.disconnect()` |
| — (no equivalent) | `AppleSignIn.instance.capabilities()` / `.diagnostics()` |

## Example

**Before:**
```dart
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

final credential = await SignInWithApple.getAppleIDCredential(
  scopes: [
    AppleIDAuthorizationScopes.email,
    AppleIDAuthorizationScopes.fullName,
  ],
);
print(credential.userIdentifier);
print(credential.identityToken);
```

**After:**
```dart
import 'package:apple_sign_in_plugin/apple_sign_in_plugin.dart';

final session = await AppleSignIn.instance.signIn(
  scopes: {AppleAuthorizationScope.email, AppleAuthorizationScope.fullName},
);
print(session.identity.userIdentifier);
print(session.authentication.identityToken);
```

## Dependency changes

Remove:
```yaml
dependencies:
  sign_in_with_apple: ^....
```

Add (currently a pre-release, so pinned exactly rather than a caret range):
```yaml
dependencies:
  apple_sign_in_plugin: 2.0.0-dev.1
```

## What's different architecturally

`apple_sign_in_plugin` does not do client-side token exchange or
revocation, and does not accept a `.p8` private key path. If your app
was passing a private key to a client-side helper, that logic must move
to your backend — see the [backend guides](backend/rest/README.md).
This is a deliberate security improvement, not a missing feature: a
private key bundled in a compiled app can be extracted, and Apple's own
guidance is that client secrets belong on a server.

## Platform support

`sign_in_with_apple` supports iOS, macOS, Android, and web.
`apple_sign_in_plugin` supports all of those plus Windows and Linux —
no platform coverage is lost by migrating.
