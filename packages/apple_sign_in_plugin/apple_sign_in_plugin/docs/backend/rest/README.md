# Backend REST Protocol — Sign in with Apple

This is a framework-agnostic reference for the backend half of Sign in
with Apple: exchanging the `authorizationCode` this plugin gives you for
tokens, and revoking access. It is the specification your own backend
implementation (in any language) needs to follow. This plugin does not
and cannot do any of this client-side — see the main README's
"Do I Need a Backend?" section for why.

## 1. Generate a client secret (JWT)

Every request below needs a `client_secret` — a JWT you sign yourself
with your Sign in with Apple private key (`.p8`), generated fresh
(Apple recommends a short lifetime, e.g. 5 minutes to 6 months max).

**Header:**
```json
{ "alg": "ES256", "kid": "<your 10-character Key ID>" }
```

**Claims:**
```json
{
  "iss": "<your 10-character Team ID>",
  "iat": 1700000000,
  "exp": 1700000300,
  "aud": "https://appleid.apple.com",
  "sub": "<your Services ID / Bundle ID>"
}
```

Sign with ES256 using your `.p8` private key. Any standard JWT library
in any language can do this — the key requirement is the `ES256`
algorithm; Apple rejects other algorithms.

**Never** embed the `.p8` file or its contents in a mobile/web/desktop
client. It must live only on your backend or a secrets manager.

## 2. Exchange the authorization code for tokens

```
POST https://appleid.apple.com/auth/token
Content-Type: application/x-www-form-urlencoded

client_id=<your Services ID / Bundle ID>
&client_secret=<JWT from step 1>
&code=<authorizationCode from the plugin>
&grant_type=authorization_code
```

A `200` response body contains `access_token`, `refresh_token`,
`id_token` (a JWT — verify its signature against Apple's public keys at
`https://appleid.apple.com/auth/keys` before trusting any claim in it),
and `expires_in`. Store `refresh_token` securely against the user's
account — it's the only long-lived credential Apple gives you.

## 3. Revoke access (true server-side revoke)

```
POST https://appleid.apple.com/auth/revoke
Content-Type: application/x-www-form-urlencoded

client_id=<your Services ID / Bundle ID>
&client_secret=<fresh JWT from step 1>
&token=<stored refresh_token>
&token_type_hint=refresh_token
```

A `200` response means Apple has revoked the grant — equivalent to the
user manually revoking your app from *Settings → Apple ID → Sign-In &
Security → Apps Using Apple ID*, except triggered by your own backend.

## 4. Verifying the identity token

Never trust `identityToken` on the client. On your backend:

1. Fetch Apple's current public keys from
   `https://appleid.apple.com/auth/keys`.
2. Verify the JWT signature against the matching key (by `kid`).
3. Verify `iss` is `https://appleid.apple.com`, `aud` matches your
   Services ID / Bundle ID, and `exp` hasn't passed.
4. Only then trust claims like `sub` (the user identifier), `email`,
   and — if you supplied one — `nonce`.

## Error responses

Both `/auth/token` and `/auth/revoke` return `400`/`401` with a JSON
body like `{"error": "invalid_grant"}` on failure. Common codes:
`invalid_client` (bad client_id/client_secret), `invalid_grant` (code
already used or expired), `invalid_request` (malformed parameters).

## Server-to-server notifications

Apple can also push events (consent revoked, email changed, account
deleted) directly to a webhook URL you register on your Services ID —
independent of whether your app is open. Configure this in the Apple
Developer Console under your Services ID's Sign in with Apple
configuration, and see Apple's own "Processing Changes to Sign in with
Apple Accounts" documentation for the payload format.
