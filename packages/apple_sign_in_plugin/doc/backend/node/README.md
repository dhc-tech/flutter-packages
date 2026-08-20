# Node.js Apple Sign-In & Revocation Service

Modern Node.js 20+ service using `jsonwebtoken` and standard fetch APIs.

```javascript
import jwt from 'jsonwebtoken';
import fs from 'fs';

export class AppleAuthService {
  constructor({ teamId, keyId, clientId, privateKeyPath }) {
    this.teamId = teamId;
    this.keyId = keyId;
    this.clientId = clientId;
    this.privateKey = fs.readFileSync(privateKeyPath, 'utf8');
  }

  generateClientSecret() {
    const claims = {
      iss: this.teamId,
      iat: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + 86400,
      aud: 'https://appleid.apple.com',
      sub: this.clientId,
    };

    return jwt.sign(claims, this.privateKey, {
      algorithm: 'ES256',
      keyid: this.keyId,
    });
  }

  async exchangeCode(code, redirectUri) {
    const secret = this.generateClientSecret();
    const params = new URLSearchParams({
      client_id: this.clientId,
      client_secret: secret,
      code,
      grant_type: 'authorization_code',
      redirect_uri: redirectUri,
    });

    const res = await fetch('https://appleid.apple.com/auth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
    });

    if (!res.ok) {
      throw new Error(`Token exchange failed (${res.status}): ${await res.text()}`);
    }
    return res.json();
  }

  async revokeToken(refreshToken) {
    const secret = this.generateClientSecret();
    const params = new URLSearchParams({
      client_id: this.clientId,
      client_secret: secret,
      token: refreshToken,
      token_type_hint: 'refresh_token',
    });

    const res = await fetch('https://appleid.apple.com/auth/revoke', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
    });

    return res.status === 200;
  }
}
```
