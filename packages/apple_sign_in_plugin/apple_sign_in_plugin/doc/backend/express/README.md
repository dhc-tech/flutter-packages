# Express.js Backend Recipe — Sign in with Apple

Wires the helpers from the [Node.js recipe](../node/README.md) into
Express endpoints your Flutter app calls after `AppleSignIn.instance.signIn()`.

```bash
npm install express jsonwebtoken
```

```js
// routes/apple-auth.js
import { Router } from 'express';
import { exchangeAuthorizationCode, revokeRefreshToken } from '../apple-auth.js';
import { saveRefreshTokenForUser, getRefreshTokenForUser } from '../db.js'; // your own storage

const router = Router();

// Called right after the Flutter app receives an AppleAuthSession.
router.post('/auth/apple/token', async (req, res) => {
  const { authorizationCode, userIdentifier } = req.body;
  if (!authorizationCode || !userIdentifier) {
    return res.status(400).json({ error: 'invalid_request' });
  }
  try {
    const tokens = await exchangeAuthorizationCode(authorizationCode);
    await saveRefreshTokenForUser(userIdentifier, tokens.refresh_token);
    // Establish your own application session however you normally do
    // (session cookie, your own JWT, etc) — do not return Apple's
    // tokens to the client.
    res.json({ success: true });
  } catch (err) {
    res.status(502).json({ error: 'apple_token_exchange_failed' });
  }
});

// Called by "Sign Out and Revoke Apple Access" / account deletion.
router.post('/auth/apple/revoke', async (req, res) => {
  const { userIdentifier } = req.body;
  const refreshToken = await getRefreshTokenForUser(userIdentifier);
  if (!refreshToken) {
    return res.status(404).json({ error: 'no_stored_credential' });
  }
  try {
    await revokeRefreshToken(refreshToken);
    res.json({ success: true });
  } catch (err) {
    res.status(502).json({ error: 'apple_revoke_failed' });
  }
});

export default router;
```

```js
// app.js
import express from 'express';
import appleAuthRouter from './routes/apple-auth.js';

const app = express();
app.use(express.json());
app.use(appleAuthRouter);
app.listen(3000);
```

On the Flutter side, call your own `/auth/apple/token` endpoint with
`session.authentication.authorizationCode` and
`session.identity.userIdentifier` right after a successful `signIn()` —
never send the authorization code anywhere except your own backend.

See the [generic REST reference](../rest/README.md) for the underlying
Apple protocol, and the [Node.js recipe](../node/README.md) for the
`exchangeAuthorizationCode`/`revokeRefreshToken` helpers used above.
