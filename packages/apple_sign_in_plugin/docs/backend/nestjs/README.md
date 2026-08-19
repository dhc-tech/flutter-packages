# NestJS Apple Authentication Module

```typescript
import { Injectable, Controller, Post, Body } from '@nestjs/common';
import * as jwt from 'jsonwebtoken';
import * as fs from 'fs';

@Injectable()
export class AppleAuthService {
  private readonly privateKey: string;

  constructor() {
    this.privateKey = fs.readFileSync(process.env.APPLE_PRIVATE_KEY_PATH, 'utf8');
  }

  generateClientSecret(): string {
    return jwt.sign(
      {
        iss: process.env.APPLE_TEAM_ID,
        iat: Math.floor(Date.now() / 1000),
        exp: Math.floor(Date.now() / 1000) + 86400,
        aud: 'https://appleid.apple.com',
        sub: process.env.APPLE_CLIENT_ID,
      },
      this.privateKey,
      {
        algorithm: 'ES256',
        keyid: process.env.APPLE_KEY_ID,
      },
    );
  }

  async revoke(refreshToken: string): Promise<boolean> {
    const res = await fetch('https://appleid.apple.com/auth/revoke', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: process.env.APPLE_CLIENT_ID,
        client_secret: this.generateClientSecret(),
        token: refreshToken,
        token_type_hint: 'refresh_token',
      }).toString(),
    });
    return res.status === 200;
  }
}

@Controller('auth/apple')
export class AppleAuthController {
  constructor(private readonly authService: AppleAuthService) {}

  @Post('revoke')
  async revoke(@Body('refreshToken') refreshToken: string) {
    const success = await this.authService.revoke(refreshToken);
    return { success };
  }
}
```
