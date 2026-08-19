# Laravel Implementation for Apple Sign-In & Revocation

Complete implementation using Laravel 11+ and `Illuminate\Support\Facades\Http`.

---

## 1. Configuration (`config/services.php`)

```php
'apple' => [
    'team_id' => env('APPLE_TEAM_ID'),
    'key_id' => env('APPLE_KEY_ID'),
    'client_id' => env('APPLE_CLIENT_ID'),
    'redirect_uri' => env('APPLE_REDIRECT_URI'),
    'private_key' => env('APPLE_PRIVATE_KEY'), // or storage_path('keys/AuthKey_XXX.p8')
],
```

## 2. Apple Authentication Service (`app/Services/AppleAuthService.php`)

```php
<?php

namespace App\Services;

use Firebase\JWT\JWT;
use Illuminate\Support\Facades\Http;
use RuntimeException;

class AppleAuthService
{
    public function generateClientSecret(): string
    {
        $key = config('services.apple.private_key');
        if (str_starts_with($key, '-----BEGIN')) {
            $privateKey = $key;
        } else {
            $privateKey = file_get_contents($key);
        }

        $payload = [
            'iss' => config('services.apple.team_id'),
            'iat' => now()->timestamp,
            'exp' => now()->addDays(2)->timestamp,
            'aud' => 'https://appleid.apple.com',
            'sub' => config('services.apple.client_id'),
        ];

        return JWT::encode($payload, $privateKey, 'ES256', config('services.apple.key_id'));
    }

    public function exchangeAuthorizationCode(string $code): array
    {
        $response = Http::asForm()->post('https://appleid.apple.com/auth/token', [
            'client_id' => config('services.apple.client_id'),
            'client_secret' => $this->generateClientSecret(),
            'code' => $code,
            'grant_type' => 'authorization_code',
            'redirect_uri' => config('services.apple.redirect_uri'),
        ]);

        if ($response->failed()) {
            throw new RuntimeException('Failed to exchange code with Apple: ' . $response->body());
        }

        return $response->json();
    }

    public function revokeToken(string $refreshToken): bool
    {
        $response = Http::asForm()->post('https://appleid.apple.com/auth/revoke', [
            'client_id' => config('services.apple.client_id'),
            'client_secret' => $this->generateClientSecret(),
            'token' => $refreshToken,
            'token_type_hint' => 'refresh_token',
        ]);

        return $response->successful();
    }
}
```

## 3. Routes & Controller (`routes/api.php`)

```php
use App\Http\Controllers\AppleAuthController;

Route::post('/auth/apple/exchange', [AppleAuthController::class, 'exchange']);
Route::post('/auth/apple/disconnect', [AppleAuthController::class, 'disconnect']);
Route::post('/auth/apple/webhook', [AppleAuthController::class, 'webhook']);
```
