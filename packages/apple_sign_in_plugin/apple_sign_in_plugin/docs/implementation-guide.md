# Implementation Guide — Zero to Working Sign in with Apple

A single, ordered walkthrough from Apple Developer Console setup to a
working client + backend. Each step links to the deeper reference for
that topic — this guide is the map, not the full detail on every stop.

## Step 1 — Apple Developer Console setup

You need these regardless of platform:

1. **App ID** (*Certificates, Identifiers & Profiles → Identifiers → App
   IDs*): enable the **Sign in with Apple** capability.
2. **Services ID** (needed for Android, Web, Windows, and Linux — the
   platforms that use the web authorization flow instead of a native
   API): create one, then configure:
   - **Domains and Subdomains**: your backend's domain (e.g.
     `api.example.com`).
   - **Return URLs**: the exact redirect URI your backend exposes
     (e.g. `https://api.example.com/auth/apple/callback`) — this must
     match the `redirectUri` you pass into the plugin's platform config
     exactly, including scheme and path.
3. **Key** (*Keys*): create a "Sign in with Apple" key, download the
   `.p8` file once (Apple will not let you download it again), and note
   its **Key ID**. This key is used **only by your backend** — see Step
   4. Also note your 10-character **Team ID** (top-right of the
   developer portal).

## Step 2 — Add the dependency

This is currently a pre-release; pin the exact version rather than
using a caret range:

```yaml
dependencies:
  apple_sign_in_plugin: 2.0.0-dev.1
```

## Step 3 — Per-platform client configuration

Every platform needs one-time setup before `signIn()` will work. Full
snippets are in the main README's "Platform Setup & Configuration"
section; summary:

| Platform | What you need | Uses your App ID or Services ID? |
|---|---|---|
| iOS / macOS | Add the **Sign in with Apple** capability in Xcode (*Signing & Capabilities*) | App ID |
| Android | Call `AppleSignInPluginAndroid.registerWith()`, then set `(AppleSignInPlatform.instance as AppleSignInAndroidImpl).config = AppleSignInAndroidConfig(serviceId, redirectUri, callbackScheme, callbackHost)` | Services ID |
| Web | Include Apple's JS SDK script tag in `web/index.html`, then set `(AppleSignInPlatform.instance as AppleSignInWebImpl).config = AppleSignInWebConfig(serviceId, redirectUri, usePopup)` | Services ID |
| Windows / Linux | Set `(AppleSignInPlatform.instance as AppleSignInWindowsImpl` / `AppleSignInLinuxImpl).config = AppleSignInDesktopConfig(serviceId, redirectUri, callbackScheme, callbackHost)` | Services ID |

Only configure the platforms you actually ship — skip the rest.

## Step 4 — Backend

You don't need a backend to get a session back from Apple — but you do
need one to:
- Verify `session.authentication.identityToken`.
- Exchange `session.authentication.authorizationCode` for a
  `refresh_token`.
- Perform true server-side revocation later.

Pick your stack and follow the matching recipe — they all implement the
same [generic REST protocol](backend/rest/README.md):

- [PHP](backend/php/README.md) · [Laravel](backend/laravel/README.md) ·
  [Node.js](backend/node/README.md) · [Express](backend/express/README.md) ·
  [NestJS](backend/nestjs/README.md)

If you want programmatic revocation from your app's "Sign Out and
Revoke" or "Delete Account" button (not just manual revocation from
Apple ID Settings), implement `AppleBackendAdapter` and set
`AppleSignIn.instance.backendAdapter` — see the README's "Sign Out vs.
Disconnect vs. True Revoke" section.

## Step 5 — Client code

```dart
import 'package:apple_sign_in_plugin/apple_sign_in_plugin.dart';

Future<void> signIn() async {
  try {
    final session = await AppleSignIn.instance.signIn(
      scopes: {AppleAuthorizationScope.email, AppleAuthorizationScope.fullName},
    );

    // Persist session.identity.name NOW — Apple only sends it once.
    if (session.lifecycle.isFirstAuthorization) {
      await saveProfile(session.identity.name);
    }

    // Send these to your backend from Step 4 — never handle them client-side.
    await myBackend.exchangeAppleCode(
      authorizationCode: session.authentication.authorizationCode!,
      userIdentifier: session.identity.userIdentifier,
    );
  } on AppleSignInException catch (e) {
    if (e.code == AppleSignInErrorCode.canceled) return;
    // Handle e.code per the README's error table.
  }
}
```

## Step 6 — Test it

1. **iOS/macOS**: run on a real device or simulator signed in with a
   real (or sandbox) Apple ID — the native sheet cannot be tested any
   other way. No unit test can substitute for this.
2. **Android/Web/Windows/Linux**: verify the browser flow completes and
   your redirect URI actually receives Apple's callback — test this
   with your Services ID's exact registered domain, not `localhost`,
   since Apple validates the domain.
3. **Second sign-in**: sign in twice with the same Apple ID and confirm
   `session.identity.name` is `null`/`isFirstAuthorization` is `false`
   the second time — this is expected Apple behavior, not a bug; make
   sure your app doesn't overwrite a previously saved name with `null`.
4. **Revocation**: manually revoke your app from *Settings → Apple ID →
   Sign-In & Security → Apps Using Apple ID*, then call
   `getCredentialState()` (iOS/macOS) and confirm it returns `revoked`.
5. **Backend**: confirm your backend's `/auth/token` call succeeds and
   `/auth/revoke` (if implemented) returns `200`.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `invalidConfiguration` on Android/Web/Windows/Linux | You called `signIn()` before setting `.config` on the platform impl (Step 3), or the redirect URI doesn't exactly match the Services ID's registered Return URL. |
| Native sheet never appears (iOS/macOS) | Missing the Sign in with Apple capability/entitlement (Step 1/3) — check `ios/Runner/Runner.entitlements` or `macos/Runner/*.entitlements`. |
| Backend `/auth/token` returns `invalid_client` | Key ID, Team ID, or Services ID mismatch in your generated client secret JWT — see [the REST reference](backend/rest/README.md#1-generate-a-client-secret-jwt). |
| Backend `/auth/token` returns `invalid_grant` | The `authorizationCode` was already used or has expired (single-use, short-lived) — don't retry with the same code. |
| `name` is `null` after the first sign-in | Expected Apple behavior — see Step 6.3. Persist it on first sign-in. |
