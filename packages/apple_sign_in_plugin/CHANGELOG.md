## 1.5.0

 - **FIX**(ci): melos release pipeline has never actually run — pin melos 6.x (#6).
 - **FEAT**(infra): add Multi-OS test matrix (Linux, macOS, Windows) and comprehensive unit tests across all packages.
 - **FEAT**(apple_sign_in_plugin): upgrade sign_in_with_apple to ^8.1.0 and bump version to 1.3.0 (#3).
 - **FEAT**(packages): add dig_cli and apple_sign_in_plugin to monorepo.
 - **DOCS**: standardize MIT license headers and holders across all monorepo packages.
 - **DOCS**: standardize all README files to official Flutter packages format.

## 1.4.0

 - **FIX**(ci): melos release pipeline has never actually run — pin melos 6.x (#6).
 - **FEAT**(infra): add Multi-OS test matrix (Linux, macOS, Windows) and comprehensive unit tests across all packages.
 - **FEAT**(apple_sign_in_plugin): upgrade sign_in_with_apple to ^8.1.0 and bump version to 1.3.0 (#3).
 - **FEAT**(packages): add dig_cli and apple_sign_in_plugin to monorepo.
 - **DOCS**: standardize MIT license headers and holders across all monorepo packages.
 - **DOCS**: standardize all README files to official Flutter packages format.

## 1.3.0
- **Dependency Upgrade**: Upgraded `sign_in_with_apple` to `^8.1.0` with full support for modern Gradle 8+ namespaces and latest Apple AuthenticationServices.
- **Cross-Platform**: Enhanced token verification and session revocation across iOS, macOS, Android, and Web.
- **Quality & Health**: 100% test coverage and full compliance with strict analyzer (`--fatal-infos`).

## 1.2.6
- **Build**: Enforced strict `dart format` to satisfy CI/CD publishing requirements.
- **Release**: Final verified build.

## 1.2.5
- **Hotfix**: Fixed Dart analyzer error where `_getTokens` return type was not guaranteed. Updated error helper to return `Never`.

## 1.2.4
- **Refactor**: Cleaned up internal error handling logic for better readability.
- **Improved**: Error messages are now professional, structured, and provide clear action items.

## 1.2.3
- **Feature**: Enhanced Error Handling. The plugin now parses Apple's error codes and suggests specific fixes (e.g., "Check your Team ID/Key ID" for `invalid_client`).
- **Safety**: Added validation to prevent running with placeholder credentials.

## 1.2.2
- **Fix**: Applied `dart format` to `example/lib/main.dart` to ensure clean git state during publishing.
- **Maintenance**: Verified clean analysis and formatting for all files.

## 1.2.1
- **Documentation**: Achieved 100% documentation coverage. Every method and parameter now has educational DartDocs.
- **Example App**: Improved UI to clearly display Backend Tokens (ID, Access, Refresh) for easier debugging.
- **User Friendly**: Major README overhaul with "Why do I need it?" explanations and clear integration steps.

## 1.2.0
- **Feature**: Full export of `sign_in_with_apple` package (including widgets like `SignInWithAppleButton`).
- **Feature**: `signInWithApple()` returns `AppleSignInResult` with tokens for backend verification.
- **CI/CD**: Fully automated publishing via GitHub Actions with OIDC authentication.

## 1.1.0
- **Breaking Change**: `signInWithApple()` now returns `AppleSignInResult` object instead of `AuthorizationCredentialAppleID`
- **Backend Ready**: Result object contains `idToken` (JWT), `accessToken`, `refreshToken`, and user details.
- **CI/CD**: Fixed version solving errors in workflows.
