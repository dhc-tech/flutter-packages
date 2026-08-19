/// Apple's assessment of whether the authenticating user is a real person,
/// mapped from `ASUserDetectionStatus` (iOS/macOS).
///
/// This is a best-effort anti-fraud signal from Apple, not a guarantee.
/// Availability depends on OS version; when unavailable this resolves to
/// [unsupported].
enum AppleRealUserStatus {
  /// This platform/OS version does not support real-user detection.
  unsupported,

  /// Apple could not determine whether the user is real.
  unknown,

  /// Apple has high confidence the user is real.
  likelyReal;

  /// Builds an [AppleRealUserStatus] from the raw integer Apple's native
  /// `ASUserDetectionStatus` enum reports over the platform channel.
  static AppleRealUserStatus fromWireValue(int? value) => switch (value) {
        1 => AppleRealUserStatus.unknown,
        2 => AppleRealUserStatus.likelyReal,
        _ => AppleRealUserStatus.unsupported,
      };
}
