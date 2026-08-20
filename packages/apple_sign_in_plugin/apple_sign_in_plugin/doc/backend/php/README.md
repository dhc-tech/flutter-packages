# Plain PHP Backend Recipe — Sign in with Apple

Uses [`firebase/php-jwt`](https://github.com/firebase/php-jwt) (the
standard, widely-used PHP JWT library) to implement the protocol from
the [generic REST reference](../rest/README.md).

```bash
composer require firebase/php-jwt
```

```php
<?php
// apple_auth.php

use Firebase\JWT\JWT;

final class AppleAuth
{
    public function __construct(
        private readonly string $teamId,
        private readonly string $keyId,
        private readonly string $clientId,      // Services ID / Bundle ID
        private readonly string $privateKeyPem, // contents of the .p8 file
    ) {}

    /** Generates a fresh Apple client secret JWT (ES256, short-lived). */
    private function generateClientSecret(): string
    {
        $now = time();
        $payload = [
            'iss' => $this->teamId,
            'iat' => $now,
            'exp' => $now + 300, // 5 minutes
            'aud' => 'https://appleid.apple.com',
            'sub' => $this->clientId,
        ];
        return JWT::encode($payload, $this->privateKeyPem, 'ES256', $this->keyId);
    }

    private function postForm(string $url, array $params): array
    {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => http_build_query($params),
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => ['Content-Type: application/x-www-form-urlencoded'],
        ]);
        $body = curl_exec($ch);
        $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        $decoded = json_decode($body, true) ?? [];
        if ($status !== 200) {
            throw new RuntimeException('Apple request failed: ' . ($decoded['error'] ?? $status));
        }
        return $decoded;
    }

    /** Exchanges an authorization code (from the Flutter app) for tokens. */
    public function exchangeAuthorizationCode(string $authorizationCode): array
    {
        return $this->postForm('https://appleid.apple.com/auth/token', [
            'client_id' => $this->clientId,
            'client_secret' => $this->generateClientSecret(),
            'code' => $authorizationCode,
            'grant_type' => 'authorization_code',
        ]);
        // Returns: access_token, refresh_token, id_token, expires_in, ...
    }

    /** Revokes a previously issued refresh token — true server-side revoke. */
    public function revokeRefreshToken(string $refreshToken): void
    {
        $this->postForm('https://appleid.apple.com/auth/revoke', [
            'client_id' => $this->clientId,
            'client_secret' => $this->generateClientSecret(),
            'token' => $refreshToken,
            'token_type_hint' => 'refresh_token',
        ]);
    }
}
```

```php
<?php
// Usage
$auth = new AppleAuth(
    teamId: getenv('APPLE_TEAM_ID'),
    keyId: getenv('APPLE_KEY_ID'),
    clientId: getenv('APPLE_CLIENT_ID'),
    privateKeyPem: getenv('APPLE_PRIVATE_KEY'),
);

$tokens = $auth->exchangeAuthorizationCode($_POST['authorizationCode']);
// Store $tokens['refresh_token'] against the user, never return Apple's
// tokens to the client.
```

See the [generic REST reference](../rest/README.md) for identity-token
verification (Apple's public keys, `firebase/php-jwt` can also verify
against them) and error codes.
