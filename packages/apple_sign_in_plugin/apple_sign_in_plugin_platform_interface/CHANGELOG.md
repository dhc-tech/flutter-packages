## 0.0.1

* Initial release. Extracted from `apple_sign_in_plugin` as part of
  federating the package into app-facing, platform-interface, and
  platform-implementation packages.
* `JwtDecoder` moved here from the app-facing package.
* `AppleAuthSession.fromCredential` now falls back to decoding the
  `email` claim from `identityToken` when the native credential response
  didn't include an email directly, so `AppleAuthIdentity.email` matches
  its documented behavior. This decode is local and unverified — it is
  not a substitute for backend identity-token verification. There is no
  equivalent fallback for `name`: Apple never embeds it in the identity
  token, so it remains available only via the native response on first
  authorization.
