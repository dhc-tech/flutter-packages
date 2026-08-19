# Node.js Backend Recipe — Sign in with Apple

A minimal, modern (Node 20+, ESM) implementation of the token
exchange/revocation flow described in the
[generic REST reference](../rest/README.md). Uses only `jsonwebtoken`
and the built-in `fetch`.

```bash
npm install jsonwebtoken
```

```js
// apple-auth.js
import jwt from 'jsonwebtoken';

const APPLE_TEAM_ID = process.env.APPLE_TEAM_ID;       // 10-char Team ID
const APPLE_KEY_ID = process.env.APPLE_KEY_ID;          // 10-char Key ID
const APPLE_CLIENT_ID = process.env.APPLE_CLIENT_ID;    // Services ID / Bundle ID
const APPLE_PRIVATE_KEY = process.env.APPLE_PRIVATE_KEY; // contents of the .p8 file

/** Generates a fresh Apple client secret JWT (ES256, short-lived). */
function generateClientSecret() {
  const now = Math.floor(Date.now() / 1000);
  return jwt.sign(
    {
      iss: APPLE_TEAM_ID,
      iat: now,
      exp: now + 300, // 5 minutes
      aud: 'https://appleid.apple.com',
      sub: APPLE_CLIENT_ID,
    },
    APPLE_PRIVATE_KEY,
    { algorithm: 'ES256', keyid: APPLE_KEY_ID },
  );
}

/** Exchanges an authorization code (from the Flutter app) for tokens. */
export async function exchangeAuthorizationCode(authorizationCode) {
  const response = await fetch('https://appleid.apple.com/auth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: APPLE_CLIENT_ID,
      client_secret: generateClientSecret(),
      code: authorizationCode,
      grant_type: 'authorization_code',
    }),
  });
  const body = await response.json();
  if (!response.ok) {
    throw new Error(`Apple token exchange failed: ${body.error}`);
  }
  return body; // { access_token, refresh_token, id_token, expires_in, ... }
}

/** Revokes a previously issued refresh token — true server-side revoke. */
export async function revokeRefreshToken(refreshToken) {
  const response = await fetch('https://appleid.apple.com/auth/revoke', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: APPLE_CLIENT_ID,
      client_secret: generateClientSecret(),
      token: refreshToken,
      token_type_hint: 'refresh_token',
    }),
  });
  if (!response.ok) {
    const body = await response.json();
    throw new Error(`Apple revoke failed: ${body.error}`);
  }
}
```

Verifying `id_token` on your own is possible (fetch
`https://appleid.apple.com/auth/keys`, match by `kid`, verify with
`jsonwebtoken`'s `jwt.verify`), or use a library such as `jwks-rsa` /
`jose` to handle key rotation for you — either is fine, this recipe
keeps dependencies minimal and leaves that choice to you.

See the [generic REST reference](../rest/README.md) for the full
protocol this wraps, including error codes and server-to-server
notifications.
