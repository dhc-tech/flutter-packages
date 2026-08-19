// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

import 'apple_authorization_scope.dart';
import 'apple_person_name.dart';
import 'apple_real_user_status.dart';

/// The result of a successful Sign in with Apple request.
///
/// Contains the user's stable identifier, authentication tokens, and any
/// profile information Apple provided.
@immutable
class AppleCredential {
  /// Creates an [AppleCredential].
  const AppleCredential({
    required this.userIdentifier,
    required this.state,
    required this.authorizedScopes,
    required this.realUserStatus,
    this.email,
    this.name,
    this.identityToken,
    this.authorizationCode,
  });

  /// The user's stable, team-scoped unique identifier.
  final String userIdentifier;

  /// The user's email address.
  final String? email;

  /// The user's full name.
  final ApplePersonName? name;

  /// A JSON Web Token (JWT) issued and signed by Apple.
  final String? identityToken;

  /// A short-lived, single-use authorization code.
  final String? authorizationCode;

  /// The state string passed to the authorization request.
  final String state;

  /// The scopes authorized by the user.
  final Set<AppleAuthorizationScope> authorizedScopes;

  /// Apple's assessment of whether the user is likely a real human.
  final AppleRealUserStatus realUserStatus;

  /// Whether this credential likely represents an initial authorization.
  bool get isFirstAuthorization => name != null && !name!.isEmpty;

  /// Returns true if Apple provided the user's name in this response.
  bool get receivedName => name != null && !name!.isEmpty;

  /// Returns true if Apple provided an email in this response or JWT claims.
  bool get receivedEmail => email != null && email!.isNotEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppleCredential &&
        other.userIdentifier == userIdentifier &&
        other.email == email &&
        other.name == name &&
        other.identityToken == identityToken &&
        other.authorizationCode == authorizationCode &&
        other.state == state &&
        setEquals(other.authorizedScopes, authorizedScopes) &&
        other.realUserStatus == realUserStatus;
  }

  @override
  int get hashCode => Object.hash(
        userIdentifier,
        email,
        name,
        identityToken,
        authorizationCode,
        state,
        Object.hashAll(authorizedScopes),
        realUserStatus,
      );

  @override
  String toString() =>
      'AppleCredential(userIdentifier: $userIdentifier, email: $email, name: $name, '
      'scopes: $authorizedScopes, realUserStatus: $realUserStatus, isFirstAuth: $isFirstAuthorization)';
}
