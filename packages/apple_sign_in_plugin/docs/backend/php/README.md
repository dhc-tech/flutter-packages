# Plain PHP 8+ Apple Sign-In & Revocation Implementation

Copy-paste ready, dependency-free implementation using PHP 8.2+ OpenSSL and cURL extensions.

---

## 1. Client Secret Generator (`AppleAuth.php`)

```php
<?php
declare(strict_types=1);

class AppleAuth {
    public function __construct(
        private readonly string $teamId,
        private readonly string $keyId,
        private readonly string $clientId,
        private readonly string $privateKeyContent
    ) {}

    public function generateClientSecret(int $expirationSeconds = 86400): string {
        $header = ['alg' => 'ES256', 'kid' => $this->keyId];
        $payload = [
            'iss' => $this->teamId,
            'iat' => time(),
            'exp' => time() + $expirationSeconds,
            'aud' => 'https://appleid.apple.com',
            'sub' => $this->clientId,
        ];

        $encodedHeader = $this->base64UrlEncode(json_encode($header, JSON_THROW_ON_ERROR));
        $encodedPayload = $this->base64UrlEncode(json_encode($payload, JSON_THROW_ON_ERROR));
        $unsignedToken = $encodedHeader . '.' . $encodedPayload;

        $privateKey = openssl_pkey_get_private($this->privateKeyContent);
        if (!$privateKey) {
            throw new RuntimeException('Invalid Apple private key.');
        }

        openssl_sign($unsignedToken, $signature, $privateKey, OPENSSL_ALGO_SHA256);
        return $unsignedToken . '.' . $this->base64UrlEncode($this->derToRaw($signature));
    }

    public function exchangeCode(string $code, string $redirectUri): array {
        $clientSecret = $this->generateClientSecret();
        $fields = [
            'client_id' => $this->clientId,
            'client_secret' => $clientSecret,
            'code' => $code,
            'grant_type' => 'authorization_code',
            'redirect_uri' => $redirectUri,
        ];

        return $this->executePost('https://appleid.apple.com/auth/token', $fields);
    }

    public function revokeToken(string $refreshToken): bool {
        $clientSecret = $this->generateClientSecret();
        $fields = [
            'client_id' => $this->clientId,
            'client_secret' => $clientSecret,
            'token' => $refreshToken,
            'token_type_hint' => 'refresh_token',
        ];

        $ch = curl_init('https://appleid.apple.com/auth/revoke');
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => http_build_query($fields),
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => ['Content-Type: application/x-www-form-urlencoded'],
        ]);
        curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        return $httpCode === 200;
    }

    private function executePost(string $url, array $data): array {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => http_build_query($data),
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => ['Content-Type: application/x-www-form-urlencoded'],
        ]);
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($httpCode !== 200) {
            throw new RuntimeException("Apple API error ($httpCode): $response");
        }
        return json_decode($response, true, 512, JSON_THROW_ON_ERROR);
    }

    private function base64UrlEncode(string $data): string {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    private function derToRaw(string $der): string {
        $pos = 0;
        if (ord($der[$pos++]) !== 0x30) return $der;
        $pos++;
        if (ord($der[$pos++]) !== 0x02) return $der;
        $lenR = ord($der[$pos++]);
        $r = substr($der, $pos, $lenR);
        $pos += $lenR;
        if (ord($der[$pos++]) !== 0x02) return $der;
        $lenS = ord($der[$pos++]);
        $s = substr($der, $pos, $lenS);

        $r = ltrim($r, "\x00");
        $s = ltrim($s, "\x00");
        return str_pad($r, 32, "\x00", STR_PAD_LEFT) . str_pad($s, 32, "\x00", STR_PAD_LEFT);
    }
}
```
