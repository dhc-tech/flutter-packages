# Apple Sign In Plugin

> **Complete Apple Authentication Lifecycle for Flutter.**  
> Supports **iOS, macOS, Android, Web (JavaScript & WebAssembly WasmGC), Windows, and Linux** with **zero third-party Apple auth SDKs**.

📘 **New to this package?** Follow the
[Implementation Guide](docs/implementation-guide.md) for an ordered,
zero-to-working walkthrough (Apple Developer Console → client → backend
→ testing). The sections below are the reference; the guide is the map.

---

## ⚡ Why This Package?

Unlike basic plugins that only show a sign-in sheet, **`apple_sign_in_plugin`** provides the entire authentication lifecycle in one unified Dart API:

* 📱 **6-Platform Native Coverage**: iOS, macOS, Android (Custom Tabs), Web (WasmGC + JS), Windows (Win32 C++), Linux (GTK C++).
* 🎯 **Structured `AppleAuthSession`**: Logical separation of `identity`, `authentication`, `authorization`, `lifecycle`, and `metadata`.
* 🔄 **Complete Lifecycle Management**: Sign in, local sign out, live credential-state polling, native revocation streams, and disconnect handling.
* 🧠 **First-Authorization Intelligence**: Accurately derives `isFirstAuthorization`, `receivedName`, and `receivedEmail` from Apple's response.
* 🛡️ **Runtime Capability Detection**: Inspect genuine OS capabilities via `AppleSignIn.instance.capabilities()` without manual OS conditionals.
* 🔍 **Zero-Secret Diagnostics**: Generate safe, copy-paste-ready environment logs for GitHub issues via `AppleSignIn.instance.diagnostics()`.
* 🔐 **Backend Optional**: Basic Sign in with Apple requires **NO server backend**. When server token exchange or true token revocation is needed, copy-paste recipes for PHP, Laravel, Node.js, Express, and NestJS are included.

---

## ⏱️ 5-Minute Quick Start

### 1. Add Dependency
Add the package to your `pubspec.yaml`. This is currently a pre-release
(`-dev`) version, so pin it exactly rather than using a caret range:
```yaml
dependencies:
  apple_sign_in_plugin: 2.0.0-dev.1
```

### 2. Basic Sign In & Read User Info
```dart
import 'package:apple_sign_in_plugin/apple_sign_in_plugin.dart';

Future<void> signInWithApple() async {
  try {
    // 1. Trigger Sign In
    final session = await AppleSignIn.instance.signIn(
      scopes: {AppleAuthorizationScope.email, AppleAuthorizationScope.fullName},
    );

    // 2. Read User Identity
    print('User Identifier: ${session.identity.userIdentifier}');
    print('Email: ${session.identity.email}');
    print('Full Name: ${session.identity.formattedName}');

    // 3. Read Authentication Tokens
    print('Identity Token JWT: ${session.authentication.identityToken}');
    print('Authorization Code: ${session.authentication.authorizationCode}');

    // 4. Check First-Time Login (Profile Data)
    if (session.lifecycle.isFirstAuthorization) {
      print('First time authorization! Save name & profile in your database.');
    }
  } on AppleSignInException catch (e) {
    if (e.code == AppleSignInErrorCode.canceled) {
      print('User cancelled sign in.');
      return;
    }
    print('Sign-in failed: ${e.message}');
  }
}
```

### 3. Local Sign Out
```dart
// Clears application session state (does NOT revoke Apple authorization)
await AppleSignIn.instance.signOut();
```

---

## 📦 Understanding `AppleAuthSession`

When `signIn()` succeeds, it returns a strongly typed **`AppleAuthSession`** structured into logical components:

```
AppleAuthSession
  ├── identity
  │    ├── userIdentifier    // Team-scoped stable user ID (e.g. "001234.abcdef...")
  │    ├── email             // Email address (from initial response or JWT claim)
  │    ├── name              // ApplePersonName (givenName, familyName, etc.)
  │    └── formattedName     // Formatted full name (e.g. "Jane Doe")
  │
  ├── authentication
  │    ├── identityToken     // Signed Apple JWT issued to your client
  │    ├── authorizationCode // Single-use authorization code for backend exchange
  │    ├── state             // Cryptographic CSRF state
  │    └── nonce             // Cryptographic nonce if passed
  │
  ├── authorization
  │    ├── scopes            // Set of granted scopes ({email, fullName})
  │    └── realUserStatus    // Apple anti-fraud status (likelyReal, unknown, unsupported)
  │
  ├── lifecycle
  │    ├── isAuthorized      // True for active valid sessions
  │    ├── isFirstAuthorization // True if Apple returned user profile data
  │    └── credentialState   // Native OS credential state (iOS/macOS only)
  │
  └── metadata
       ├── receivedName      // True if Apple provided structured name
       ├── receivedEmail     // True if email was provided
       └── capabilities      // Platform capability snapshot at time of sign-in
```

> **Important (First Authorization):** Apple returns the user's `name` **only on the very first authorization**. On subsequent sign-ins, Apple omits the name object. Your application must persist the user's name upon initial sign-in.

> **Email fallback:** `identity.email` is read directly from the native
> response when present, and falls back to decoding the `email` claim
> out of `authentication.identityToken` when it isn't (this decode is
> local, unverified, and best-effort — see "Security" below). **`name`
> has no such fallback** — Apple never embeds the name in the identity
> token, so it is only ever available via the native response on first
> authorization. If you didn't persist it then, it cannot be recovered
> later by any means, including JWT decoding.

---

## 🔄 Authentication Lifecycle & Events

Listen to high-level authentication lifecycle changes across your application:

```dart
AppleSignIn.instance.events.listen((event) {
  switch (event.type) {
    case AppleAuthEventType.signedIn:
      print('User signed in: ${event.userIdentifier}');
    case AppleAuthEventType.signedOut:
      print('User signed out locally: ${event.userIdentifier}');
    case AppleAuthEventType.credentialRevoked:
      print('Apple ID permission revoked in Apple ID Settings (Native Notification).');
    case AppleAuthEventType.credentialTransferred:
      print('App transferred to another developer team; user migration required.');
    case AppleAuthEventType.authorizationCancelled:
      print('User dismissed the Apple Sign-In sheet/window.');
    case AppleAuthEventType.sessionChanged:
      print('Authentication session state changed.');
  }
});
```

---

## 🔎 Checking Native Credential State (iOS & macOS)

On native Apple platforms (iOS and macOS), you can verify whether the user's Apple ID session remains valid at app launch:

```dart
final state = await AppleSignIn.instance.getCredentialState(userIdentifier);

switch (state) {
  case AppleCredentialState.authorized:
    print('User credential is valid and authorized.');
  case AppleCredentialState.revoked:
    print('User revoked access in Apple ID Settings. Prompt to re-login.');
  case AppleCredentialState.notFound:
    print('User not found. Prompt user to sign in.');
  case AppleCredentialState.transferred:
    print('App transferred to a new team. Migrate identifier via Apple Transfer API.');
}
```

> **Note on other platforms:** Android, Web, Windows, and Linux do not expose a client-side Apple credential state API. Calling `getCredentialState()` on non-Apple platforms throws an `AppleSignInException(AppleSignInErrorCode.platformNotSupported)`.

---

## 🚪 Sign Out vs. Disconnect vs. True Revoke

| Operation | What It Does | Backend Required? |
| :--- | :--- | :---: |
| **`signOut()`** | Clears the local application session on the device. Does **NOT** revoke Apple authorization. | ❌ No |
| **`disconnect()`** | Checks native credential state and evaluates whether server revocation or manual action is needed. | ❌ No |
| **True Apple Revoke** | Programmatically invalidates the Apple token by calling `POST https://appleid.apple.com/auth/revoke`. | ✅ **Yes** (Requires `.p8` key on server) |
| **Account Deletion** | Deletes user record in database + invokes True Apple Revoke. | ✅ **Yes** |

### Using `AppleSignIn.instance.disconnect()`
```dart
final result = await AppleSignIn.instance.disconnect(userIdentifier: userId);

print('Status: ${result.status}');
print('Message: ${result.message}');

// Possible statuses (AppleDisconnectStatus):
// - revoked               Programmatically revoked — returned by your AppleBackendAdapter.
// - alreadyRevoked        Apple already shows the credential as revoked.
// - notAuthorized         No active session/credential was found for this user.
// - manualActionRequired  No AppleBackendAdapter configured; instruct the user to
//                         remove the app in Apple ID Settings themselves.
// - backendRequired       Non-Apple platform: true revocation needs an
//                         AppleBackendAdapter to call Apple's /auth/revoke.
// - unsupported           Programmatic revocation isn't possible here without one.
// - failed                Your AppleBackendAdapter attempted revocation and it failed.
```

---

## 🌐 Do I Need a Backend?

### ❌ You do NOT need a backend for:
* Basic Sign in with Apple on iOS, macOS, Android, Web, Windows, and Linux.
* Retrieving user identifier, email, name, identity token JWT, and auth code.
* Local application sign-out (`signOut()`).
* Native credential state queries and revocation streams on iOS and macOS.

### ✅ You DO need a backend for:
* Exchanging `authorizationCode` for persistent `refresh_token`.
* True programmatic token revocation (`POST https://appleid.apple.com/auth/revoke`) during Account Deletion.
* Handling Apple Server-to-Server notifications (Consent Revoked, Account Deleted).

---

## 📚 Official Backend Guides & Recipes

Complete, copy-paste recipes with zero third-party Apple SDKs:

* 📖 [Generic REST Protocol Reference](docs/backend/rest/README.md)
* 🐘 [Plain PHP Implementation](docs/backend/php/README.md)
* 🔴 [Laravel Service & Controller Recipe](docs/backend/laravel/README.md)
* 🟩 [Node.js Implementation](docs/backend/node/README.md)
* 🚂 [Express.js Endpoints](docs/backend/express/README.md)
* 🐈 [NestJS Auth Module](docs/backend/nestjs/README.md)
* 🔄 [Migration Guide from `sign_in_with_apple`](docs/migration-from-sign-in-with-apple.md)

---

## 🛠️ Platform Setup & Configuration

### 1. iOS & macOS Setup
In Xcode, open `ios/Runner.xcworkspace` or `macos/Runner.xcworkspace`:
1. Go to **Signing & Capabilities** -> Click **+ Capability** -> Add **Sign in with Apple**.
2. Ensure your Apple Developer Provisioning Profile includes the Sign in with Apple capability.

### 2. Android Setup
1. Configure an **Apple Services ID** and **HTTPS Redirect URI** in the Apple Developer Console.
2. In your Flutter app initialization:
```dart
import 'package:apple_sign_in_plugin_android/apple_sign_in_plugin_android.dart';

AppleSignInPluginAndroid.registerWith();
(AppleSignInPlatform.instance as AppleSignInAndroidImpl).config = const AppleSignInAndroidConfig(
  serviceId: 'com.example.service',
  redirectUri: 'https://api.example.com/auth/apple/callback',
  callbackScheme: 'com.example.app',
  callbackHost: 'apple-callback',
);
```

### 3. Web & WebAssembly (WasmGC) Setup
Include Apple's official JS SDK in your `web/index.html`:
```html
<script type="text/javascript" src="https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js"></script>
```
Configure your Services ID:
```dart
import 'package:apple_sign_in_plugin_web/apple_sign_in_plugin_web.dart';

(AppleSignInPlatform.instance as AppleSignInWebImpl).config = const AppleSignInWebConfig(
  serviceId: 'com.example.service',
  redirectUri: 'https://api.example.com/auth/apple/callback',
  usePopup: true,
);
```

### 4. Windows & Linux Setup
Configure desktop OAuth parameters matching your registered Services ID:
```dart
import 'package:apple_sign_in_plugin_windows/apple_sign_in_plugin_windows.dart';

(AppleSignInPlatform.instance as AppleSignInWindowsImpl).config = const AppleSignInDesktopConfig(
  serviceId: 'com.example.service',
  redirectUri: 'https://api.example.com/auth/apple/callback',
  callbackScheme: 'com.example.app',
  callbackHost: 'apple-callback',
);
```

---

## 🛡️ Capabilities & Diagnostics

### Runtime Capability Detection
Check platform support dynamically without writing fragile OS checks:
```dart
final caps = await AppleSignIn.instance.capabilities();

if (caps.nativeCredentialState) {
  // Safe to call getCredentialState()
}
if (caps.wasmWeb) {
  // Running on WebAssembly-compatible runtime
}
```

### Safe Environment Diagnostics
Export diagnostic information that is completely safe to paste into GitHub issues (contains zero tokens, nonces, or secrets):
```dart
final diag = await AppleSignIn.instance.diagnostics();
debugPrint(diag.toSafeString());
```
Example Output:
```text
=== Apple Sign-In Diagnostics ===
Platform: iOS
Available: true
Configured: true
Native Credential State Supported: true
Revocation Stream Supported: true
WebAssembly Supported: false
Backend Adapter Registered: false
```

---

## ⚠️ Common Error Codes & Resolutions

All values below are members of the `AppleSignInErrorCode` enum, read
via `AppleSignInException.code`.

| Error Code | Meaning | Recommended Developer Action |
| :--- | :--- | :--- |
| `canceled` | User closed the Apple sheet/window. | Ignore or silently reset UI state — not a real failure. |
| `alreadyInProgress` | Another sign-in request is active. | Debounce user taps on the Sign in button. |
| `notAvailable` | Sign in with Apple isn't available on this device/OS version. | Check `capabilities()` before showing the button. |
| `invalidArguments` | Arguments passed to the plugin were invalid (e.g. empty scopes). | Fix the call site — this indicates a bug in your app code. |
| `invalidConfiguration` | Missing entitlement, bad Services ID, or bad redirect URI. | Re-check platform setup in the README's configuration section. |
| `authorizationFailed` | The native authorization request failed for another reason. | Show a generic error and let the user retry. |
| `invalidResponse` | The platform returned a response the plugin couldn't parse. | Usually transient; let the user retry. |
| `networkFailed` | A network request required to complete the flow failed. | Prompt the user to check connectivity and retry. |
| `credentialStateFailed` | `getCredentialState()` itself failed. | Treat as unknown state; don't assume revoked. |
| `platformNotSupported` | The called feature isn't implemented on this platform. | Check `capabilities()` before calling platform-specific APIs. |
| `unknown` | An error that doesn't fit any code above. | Log `exception.message` for diagnostics. |

---

## ❓ Frequently Asked Questions (FAQ)

#### Q: Do I need a backend to use this plugin?
**A:** No. Basic sign-in on all 6 platforms works completely out of the box without any backend.

#### Q: Why is `name` null on the second login?
**A:** Apple only returns the user's name on their **first authorization**. You must persist the name in your local/remote database upon initial sign-in.

#### Q: Can I revoke Apple authorization from the Flutter app without a server?
**A:** No. Apple's `POST /auth/revoke` endpoint requires a Client Secret signed by your `.p8` private key using ES256. Private keys must **never** be embedded into client apps.

#### Q: Where should my `.p8` private key be stored?
**A:** Only on your secure backend server or cloud secret manager. Never in your Flutter project or app bundle.

#### Q: What does `CredentialState.transferred` mean?
**A:** It means the app was transferred to a different Apple Developer Team. The user identifier must be migrated using Apple's User Migration API.

---

## 📄 License

MIT License. Developed by DHC Tech.
