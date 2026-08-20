# Express.js Apple Authentication Endpoints

```javascript
import express from 'express';
import { AppleAuthService } from '../node/README.js';

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const appleAuth = new AppleAuthService({
  teamId: process.env.APPLE_TEAM_ID,
  keyId: process.env.APPLE_KEY_ID,
  clientId: process.env.APPLE_CLIENT_ID,
  privateKeyPath: process.env.APPLE_KEY_PATH,
});

// 1. Authorization Code Exchange
app.post('/api/auth/apple/exchange', async (req, res) => {
  try {
    const { code, redirectUri } = req.body;
    const tokens = await appleAuth.exchangeCode(code, redirectUri);
    // Save tokens.refresh_token securely with user account
    res.json({ success: true, userIdentifier: tokens.id_token });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// 2. Account Disconnect / Revoke
app.post('/api/auth/apple/revoke', async (req, res) => {
  try {
    const { userId } = req.body;
    const user = await db.getUser(userId);
    const success = await appleAuth.revokeToken(user.appleRefreshToken);
    res.json({ success, status: success ? 'revoked' : 'failed' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 3. Apple Server-to-Server Webhook
app.post('/api/auth/apple/webhook', async (req, res) => {
  // Apple sends payload with JWE/JWT notification
  res.status(200).send('OK');
});

app.listen(3000, () => console.log('Auth server listening on port 3000'));
```
