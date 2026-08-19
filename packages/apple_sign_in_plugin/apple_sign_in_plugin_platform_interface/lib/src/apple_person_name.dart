import 'package:flutter/foundation.dart' show immutable;

/// A structured representation of the name Apple returns for a user.
///
/// Apple only ever populates these components; it never returns a single
/// pre-formatted display string, so this plugin does not synthesize one
/// either. Apple also only returns name data on the **first** authorization
/// a user grants to your app/Service ID — your app is responsible for
/// persisting it (see the README's "Full Name" section).
@immutable
class ApplePersonName {
  /// Creates an [ApplePersonName] from its individual components.
  ///
  /// Every field is exactly what Apple provided — nothing here is guessed
  /// or derived.
  const ApplePersonName({
    this.namePrefix,
    this.givenName,
    this.middleName,
    this.familyName,
    this.nameSuffix,
    this.nickname,
  });

  /// Honorific prefix, e.g. `"Dr."`.
  final String? namePrefix;

  /// Given (first) name.
  final String? givenName;

  /// Middle name.
  final String? middleName;

  /// Family (last) name.
  final String? familyName;

  /// Honorific suffix, e.g. `"Jr."`.
  final String? nameSuffix;

  /// Nickname, when Apple provides one.
  final String? nickname;

  /// Whether every component of this name is `null`.
  bool get isEmpty =>
      namePrefix == null &&
      givenName == null &&
      middleName == null &&
      familyName == null &&
      nameSuffix == null &&
      nickname == null;

  @override
  String toString() =>
      'ApplePersonName(namePrefix: $namePrefix, givenName: $givenName, '
      'middleName: $middleName, familyName: $familyName, '
      'nameSuffix: $nameSuffix, nickname: $nickname)';

  @override
  bool operator ==(Object other) =>
      other is ApplePersonName &&
      other.namePrefix == namePrefix &&
      other.givenName == givenName &&
      other.middleName == middleName &&
      other.familyName == familyName &&
      other.nameSuffix == nameSuffix &&
      other.nickname == nickname;

  @override
  int get hashCode => Object.hash(
    namePrefix,
    givenName,
    middleName,
    familyName,
    nameSuffix,
    nickname,
  );
}
