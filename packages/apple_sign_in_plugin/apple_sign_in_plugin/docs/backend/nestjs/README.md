# NestJS Backend Recipe — Sign in with Apple

A NestJS module wrapping the same protocol as the
[generic REST reference](../rest/README.md).

```bash
npm install jsonwebtoken @nestjs/config
```

```ts
// apple-auth/apple-auth.service.ts
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as jwt from 'jsonwebtoken';

export interface AppleTokenResponse {
  access_token: string;
  refresh_token: string;
  id_token: string;
  expires_in: number;
}

@Injectable()
export class AppleAuthService {
  constructor(private readonly config: ConfigService) {}

  private generateClientSecret(): string {
    const now = Math.floor(Date.now() / 1000);
    return jwt.sign(
      {
        iss: this.config.getOrThrow<string>('APPLE_TEAM_ID'),
        iat: now,
        exp: now + 300,
        aud: 'https://appleid.apple.com',
        sub: this.config.getOrThrow<string>('APPLE_CLIENT_ID'),
      },
      this.config.getOrThrow<string>('APPLE_PRIVATE_KEY'),
      { algorithm: 'ES256', keyid: this.config.getOrThrow<string>('APPLE_KEY_ID') },
    );
  }

  async exchangeAuthorizationCode(authorizationCode: string): Promise<AppleTokenResponse> {
    const response = await fetch('https://appleid.apple.com/auth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: this.config.getOrThrow<string>('APPLE_CLIENT_ID'),
        client_secret: this.generateClientSecret(),
        code: authorizationCode,
        grant_type: 'authorization_code',
      }),
    });
    if (!response.ok) {
      throw new Error(`Apple token exchange failed: ${response.status}`);
    }
    return response.json();
  }

  async revokeRefreshToken(refreshToken: string): Promise<void> {
    const response = await fetch('https://appleid.apple.com/auth/revoke', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: this.config.getOrThrow<string>('APPLE_CLIENT_ID'),
        client_secret: this.generateClientSecret(),
        token: refreshToken,
        token_type_hint: 'refresh_token',
      }),
    });
    if (!response.ok) {
      throw new Error(`Apple revoke failed: ${response.status}`);
    }
  }
}
```

```ts
// apple-auth/apple-auth.controller.ts
import { Body, Controller, Post } from '@nestjs/common';
import { AppleAuthService } from './apple-auth.service';
import { UserCredentialStore } from './user-credential.store'; // your own storage

@Controller('auth/apple')
export class AppleAuthController {
  constructor(
    private readonly appleAuth: AppleAuthService,
    private readonly credentials: UserCredentialStore,
  ) {}

  @Post('token')
  async exchange(
    @Body() body: { authorizationCode: string; userIdentifier: string },
  ) {
    const tokens = await this.appleAuth.exchangeAuthorizationCode(body.authorizationCode);
    await this.credentials.saveRefreshToken(body.userIdentifier, tokens.refresh_token);
    return { success: true };
  }

  @Post('revoke')
  async revoke(@Body() body: { userIdentifier: string }) {
    const refreshToken = await this.credentials.getRefreshToken(body.userIdentifier);
    await this.appleAuth.revokeRefreshToken(refreshToken);
    return { success: true };
  }
}
```

```ts
// apple-auth/apple-auth.module.ts
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppleAuthService } from './apple-auth.service';
import { AppleAuthController } from './apple-auth.controller';

@Module({
  imports: [ConfigModule],
  providers: [AppleAuthService],
  controllers: [AppleAuthController],
  exports: [AppleAuthService],
})
export class AppleAuthModule {}
```

See the [generic REST reference](../rest/README.md) for the underlying
protocol, error codes, and identity-token verification steps.
