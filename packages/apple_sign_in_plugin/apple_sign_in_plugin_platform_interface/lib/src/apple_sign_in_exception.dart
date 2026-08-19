/// Stable, cross-platform error codes for Apple Sign-In failures.
///
/// Native error domains differ per platform (`ASAuthorizationError` on
/// Apple platforms, HTTP/JS errors elsewhere); every implementation maps
/// its native errors onto this fixed set so callers never need to branch
/// on platform-specific exception types.
enum AppleSignInErrorCode {
  /// The user canceled the authorization sheet/flow.
  canceled,

  /// Another authorization request is already in progress.
  alreadyInProgress,

  /// Sign in with Apple is not available on this device/platform/OS
  /// version.
  notAvailable,

  /// The arguments passed to the plugin were invalid (e.g. empty scopes).
  invalidArguments,

  /// The plugin/app is misconfigured (missing entitlement, bad Service ID,
  /// bad redirect URI, etc).
  invalidConfiguration,

  /// The native authorization request failed for a reason not covered by
  /// a more specific code above.
  authorizationFailed,

  /// The platform returned a response the plugin could not parse.
  invalidResponse,

  /// A network request required to complete the flow failed.
  networkFailed,

  /// [AppleSignInPlugin.getCredentialState] failed.
  credentialStateFailed,

  /// The requested feature is not implemented on the current platform yet.
  ///
  /// See the package README's platform-support table.
  platformNotSupported,

  /// An error occurred that doesn't fit any of the above.
  unknown,
}

/// Thrown for all Apple Sign-In failures raised by this plugin.
///
/// Always check [code] first — it is stable across platform and SDK
/// versions. [message] is a human-readable detail string suitable for
/// debug logs, not for parsing.
class AppleSignInException implements Exception {
  /// Creates an [AppleSignInException].
  const AppleSignInException(this.code, this.message, [this.details]);

  /// The stable, cross-platform error category.
  final AppleSignInErrorCode code;

  /// A human-readable description of what went wrong.
  final String message;

  /// Optional additional platform-specific detail, if any was provided.
  final Object? details;

  @override
  String toString() => 'AppleSignInException(${code.name}): $message';
}
