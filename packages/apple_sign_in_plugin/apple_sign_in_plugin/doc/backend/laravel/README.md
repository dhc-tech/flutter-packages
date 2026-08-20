# Laravel Backend Recipe — Sign in with Apple

Wraps the same [`firebase/php-jwt`](https://github.com/firebase/php-jwt)
approach as the [plain PHP recipe](../php/README.md) in a Laravel
service + controller.

```bash
composer require firebase/php-jwt
```

```php
<?php
// config/apple.php

return [
    'team_id' => env('APPLE_TEAM_ID'),
    'key_id' => env('APPLE_KEY_ID'),
    'client_id' => env('APPLE_CLIENT_ID'),
    'private_key' => env('APPLE_PRIVATE_KEY'), // contents of the .p8 file
];
```

```php
<?php
// app/Services/AppleAuthService.php

namespace App\Services;

use Firebase\JWT\JWT;
use Illuminate\Support\Facades\Http;
use RuntimeException;

class AppleAuthService
{
    private function generateClientSecret(): string
    {
        $now = time();
        $payload = [
            'iss' => config('apple.team_id'),
            'iat' => $now,
            'exp' => $now + 300,
            'aud' => 'https://appleid.apple.com',
            'sub' => config('apple.client_id'),
        ];
        return JWT::encode($payload, config('apple.private_key'), 'ES256', config('apple.key_id'));
    }

    public function exchangeAuthorizationCode(string $authorizationCode): array
    {
        $response = Http::asForm()->post('https://appleid.apple.com/auth/token', [
            'client_id' => config('apple.client_id'),
            'client_secret' => $this->generateClientSecret(),
            'code' => $authorizationCode,
            'grant_type' => 'authorization_code',
        ]);

        if ($response->failed()) {
            throw new RuntimeException('Apple token exchange failed: ' . $response->json('error'));
        }
        return $response->json(); // access_token, refresh_token, id_token, expires_in
    }

    public function revokeRefreshToken(string $refreshToken): void
    {
        $response = Http::asForm()->post('https://appleid.apple.com/auth/revoke', [
            'client_id' => config('apple.client_id'),
            'client_secret' => $this->generateClientSecret(),
            'token' => $refreshToken,
            'token_type_hint' => 'refresh_token',
        ]);

        if ($response->failed()) {
            throw new RuntimeException('Apple revoke failed: ' . $response->json('error'));
        }
    }
}
```

```php
<?php
// app/Http/Controllers/AppleAuthController.php

namespace App\Http\Controllers;

use App\Services\AppleAuthService;
use App\Models\User;
use Illuminate\Http\Request;

class AppleAuthController extends Controller
{
    public function __construct(private readonly AppleAuthService $appleAuth) {}

    public function exchange(Request $request)
    {
        $validated = $request->validate([
            'authorizationCode' => 'required|string',
            'userIdentifier' => 'required|string',
        ]);

        $tokens = $this->appleAuth->exchangeAuthorizationCode($validated['authorizationCode']);

        User::where('apple_user_identifier', $validated['userIdentifier'])
            ->update(['apple_refresh_token' => encrypt($tokens['refresh_token'])]);

        return response()->json(['success' => true]);
    }

    public function revoke(Request $request)
    {
        $validated = $request->validate(['userIdentifier' => 'required|string']);

        $user = User::where('apple_user_identifier', $validated['userIdentifier'])->firstOrFail();
        $this->appleAuth->revokeRefreshToken(decrypt($user->apple_refresh_token));

        return response()->json(['success' => true]);
    }
}
```

```php
<?php
// routes/api.php
Route::post('/auth/apple/token', [AppleAuthController::class, 'exchange']);
Route::post('/auth/apple/revoke', [AppleAuthController::class, 'revoke']);
```

Store `apple_refresh_token` **encrypted** (Laravel's `encrypt()`/`decrypt()`
helpers, shown above, use your app's `APP_KEY`). See the
[generic REST reference](../rest/README.md) for identity-token
verification and error codes.
