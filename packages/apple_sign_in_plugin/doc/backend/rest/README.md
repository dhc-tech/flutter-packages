# Apple Sign-In Generic REST API & Security Specification

This guide details the framework-agnostic architecture and exact HTTP request/response semantics for integrating your application backend with Apple's authentication servers.

---

## 1. Architectural Overview

```
┌──────────────┐                 ┌──────────────────────┐                 ┌─────────────────────┐
│ Flutter App  │                 │  Application Backend │                 │ Apple Auth Servers  │
│ (Any OS/Web) │                 │  (Node/PHP/Go/etc.)  │                 │ (appleid.apple.com) │
└──────┬───────┘                 └──────────┬───────────┘                 └──────────┬──────────┘
       │                                    │                                        │
       │ 1. Complete Apple Authorization    │                                        │
       │    (Sheet, CustomTab, or Web JS)   │                                        │
       │───────────────────────────────────>│                                        │
       │                                    │                                        │
       │ 2. Send authorizationCode & JWT    │                                        │
       │───────────────────────────────────>│                                        │
       │                                    │ 3. Generate ES256 Client Secret JWT    │
       │                                    │    with private .p8 key                │
       │                                    │───────────────────────────────────────>│
       │                                    │                                        │
       │                                    │ 4. POST /auth/token (Validate code)    │
       │                                    │───────────────────────────────────────>│
       │                                    │                                        │
       │                                    │ 5. Returns refresh_token & id_token    │
       │                                    │<───────────────────────────────────────│
       │                                    │                                        │
       │ 6. App Disconnect / Account Delete │                                        │
       │───────────────────────────────────>│                                        │
       │                                    │ 7. POST /auth/revoke (Revoke token)    │
       │                                    │───────────────────────────────────────>│
       │                                    │                                        │
       │                                    │ 8. Apple Revocation 200 OK             │
       │                                    │<───────────────────────────────────────│
```

---

## 2. Generating the Client Secret JWT

Apple requires all backend REST API requests to authenticate using a JSON Web Token (JWT) signed with the **ES256 (ECDSA with P-256 and SHA-256)** algorithm using your developer `.p8` private key.

### JWT Header:
```json
{
  "alg": "ES256",
  "kid": "ABC123DEFG"
}
```

### JWT Payload:
```json
{
  "iss": "TEAM123456",
  "iat": 1724000000,
  "exp": 1724086400,
  "aud": "https://appleid.apple.com",
  "sub": "com.example.service"
}
```
* `iss`: 10-character Apple Developer **Team ID**.
* `iat`: Current Unix timestamp in seconds.
* `exp`: Expiration timestamp (maximum 6 months = 15777000 seconds).
* `aud`: Always `"https://appleid.apple.com"`.
* `sub`: Your **Services ID** (for web/Android/Windows/Linux) or **Bundle ID** (for iOS/macOS).

---

## 3. Token Exchange Endpoint (`/auth/token`)

### Request:
```http
POST https://appleid.apple.com/auth/token
Content-Type: application/x-www-form-urlencoded

client_id=com.example.service
&client_secret=<CLIENT_SECRET_JWT>
&code=<AUTHORIZATION_CODE_FROM_FLUTTER>
&grant_type=authorization_code
&redirect_uri=https://api.example.com/auth/apple/callback
```

### Success Response (`200 OK`):
```json
{
  "access_token": "a1b2c3d4...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "r1s2t3u4...",
  "id_token": "eyJhbGciOi..."
}
```

> **Security Rule:** Securely persist `refresh_token` in your database encrypted at rest. It is required later to execute token revocation when the user deletes their account.

---

## 4. True Token Revocation Endpoint (`/auth/revoke`)

### Request:
```http
POST https://appleid.apple.com/auth/revoke
Content-Type: application/x-www-form-urlencoded

client_id=com.example.service
&client_secret=<CLIENT_SECRET_JWT>
&token=<STORED_REFRESH_TOKEN>
&token_type_hint=refresh_token
```

### Success Response:
* Status Code: `200 OK` (Empty response body).
