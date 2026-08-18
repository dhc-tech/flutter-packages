# Skill: apple_sign_in_plugin Authentication

## Overview
`apple_sign_in_plugin` provides Apple Sign-In authentication across iOS, macOS, Android, and Web platforms.

## Key Principles
- Uses native `AuthenticationServices` on iOS 13+ and macOS 10.15+.
- Uses Apple Sign In via web OAuth/REST flow for Android and Web.
- Returns verified `idToken` (JWT) and `authorizationCode` for server verification.
