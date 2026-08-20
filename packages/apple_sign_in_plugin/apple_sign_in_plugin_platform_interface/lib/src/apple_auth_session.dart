// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

import 'apple_authorization_scope.dart';
import 'apple_credential.dart';
import 'apple_credential_state.dart';
import 'apple_person_name.dart';
import 'apple_real_user_status.dart';
import 'apple_sign_in_capabilities.dart';
import 'jwt_decoder.dart';

/// Extracts the `email` claim from an Apple identity token, for use only
/// as a fallback when the native credential response didn't include an
/// email directly.
///
/// This never verifies the token's signature — it must not be treated as
/// a substitute for backend-side identity verification (see the package
/// README's "Backend Boundary" section) — it is purely a best-effort
/// convenience so [AppleAuthIdentity.email] is populated whenever Apple
/// provided the claim by either means. Returns `null` on any decode
/// failure rather than throwing, since a malformed/missing email claim
/// must never break the sign-in flow.
String? _decodeEmailFromIdentityToken(String? identityToken) {
  if (identityToken == null) {
    return null;
  }
  final Map<String, dynamic>? claims = JwtDecoder.tryDecode(identityToken);
  final Object? email = claims?['email'];
  return (email is String && email.isNotEmpty) ? email : null;
}

/// User identity details provided by Apple.
@immutable
class AppleAuthIdentity {
  /// Creates an [AppleAuthIdentity].
  const AppleAuthIdentity({
    required this.userIdentifier,
    this.email,
    this.name,
  });

  /// The user's team-scoped stable unique identifier.
  final String userIdentifier;

  /// The user's email address (from initial authorization or identity token JWT claims).
  final String? email;

  /// The user's structured full name (available on initial authorization).
  final ApplePersonName? name;

  /// Returns the formatted full name if available.
  String? get formattedName {
    if (name == null || name!.isEmpty) {
      return null;
    }
    final Iterable<String> parts = [name!.givenName, name!.familyName]
        .whereType<String>()
        .where((s) => s.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' ');
  }

  @override
  String toString() =>
      'AppleAuthIdentity(userIdentifier: $userIdentifier, email: $email, name: $formattedName)';
}

/// Authentication tokens and request correlation parameters.
@immutable
class AppleAuthTokens {
  /// Creates an [AppleAuthTokens].
  const AppleAuthTokens({
    required this.state,
    this.identityToken,
    this.authorizationCode,
    this.nonce,
  });

  /// A JSON Web Token (JWT) issued and signed by Apple.
  final String? identityToken;

  /// A short-lived, single-use authorization code for server-side token exchange.
  final String? authorizationCode;

  /// The cryptographic CSRF state parameter passed during the authorization request.
  final String state;

  /// The cryptographic nonce passed during the authorization request, if any.
  final String? nonce;

  /// Custom toString that prevents leaking sensitive authorization tokens or codes.
  @override
  String toString() =>
      'AppleAuthTokens(hasIdentityToken: ${identityToken != null}, hasAuthCode: ${authorizationCode != null}, state: $state)';
}

/// Granted scopes and user authenticity assessment.
@immutable
class AppleAuthAuthorization {
  /// Creates an [AppleAuthAuthorization].
  const AppleAuthAuthorization({
    required this.scopes,
    required this.realUserStatus,
  });

  /// The set of authorization scopes granted by the user.
  final Set<AppleAuthorizationScope> scopes;

  /// Apple's assessment of whether the user is likely a real human.
  final AppleRealUserStatus realUserStatus;

  @override
  String toString() =>
      'AppleAuthAuthorization(scopes: $scopes, realUserStatus: $realUserStatus)';
}

/// Session status and native credential state information.
@immutable
class AppleAuthLifecycle {
  /// Creates an [AppleAuthLifecycle].
  const AppleAuthLifecycle({
    required this.isAuthorized,
    required this.isFirstAuthorization,
    this.credentialState,
  });

  /// Whether the session is currently authenticated and valid.
  final bool isAuthorized;

  /// Whether this session represents an initial authorization (profile information provided).
  final bool isFirstAuthorization;

  /// The native credential state on Apple platforms (or null on platforms without a native state query).
  final AppleCredentialState? credentialState;

  @override
  String toString() =>
      'AppleAuthLifecycle(isAuthorized: $isAuthorized, isFirstAuth: $isFirstAuthorization, credentialState: $credentialState)';
}

/// Metadata indicating what data was provided in the Apple authorization response.
@immutable
class AppleAuthMetadata {
  /// Creates an [AppleAuthMetadata].
  const AppleAuthMetadata({
    required this.receivedName,
    required this.receivedEmail,
    required this.capabilities,
    required this.createdAt,
  });

  /// Whether Apple provided the user's structured name in this response.
  final bool receivedName;

  /// Whether an email was provided in the response or decoded from identity token claims.
  final bool receivedEmail;

  /// The active platform capabilities at the time this session was established.
  final AppleSignInCapabilities capabilities;

  /// When this session was created.
  final DateTime createdAt;

  @override
  String toString() =>
      'AppleAuthMetadata(receivedName: $receivedName, receivedEmail: $receivedEmail, platform: ${capabilities.platformName})';
}

/// A complete, strongly-typed Apple Authentication Session.
///
/// Logically structures identity, authentication tokens, authorization grants,
/// lifecycle status, and response metadata.
@immutable
class AppleAuthSession {
  /// Creates an [AppleAuthSession].
  const AppleAuthSession({
    required this.identity,
    required this.authentication,
    required this.authorization,
    required this.lifecycle,
    required this.metadata,
    required this.rawCredential,
  });

  /// Factory constructing [AppleAuthSession] from an [AppleCredential].
  factory AppleAuthSession.fromCredential({
    required AppleCredential credential,
    required AppleSignInCapabilities capabilities,
    String? nonce,
    AppleCredentialState? credentialState,
  }) {
    // Apple always sends `email` directly on the credential when the scope
    // was granted, but as a fallback for platforms/flows that only surface
    // it via the identity token, decode it from there too.
    final String? resolvedEmail = credential.email ??
        _decodeEmailFromIdentityToken(credential.identityToken);

    return AppleAuthSession(
      identity: AppleAuthIdentity(
        userIdentifier: credential.userIdentifier,
        email: resolvedEmail,
        name: credential.name,
      ),
      authentication: AppleAuthTokens(
        identityToken: credential.identityToken,
        authorizationCode: credential.authorizationCode,
        state: credential.state,
        nonce: nonce,
      ),
      authorization: AppleAuthAuthorization(
        scopes: credential.authorizedScopes,
        realUserStatus: credential.realUserStatus,
      ),
      lifecycle: AppleAuthLifecycle(
        isAuthorized: true,
        isFirstAuthorization: credential.isFirstAuthorization,
        credentialState: credentialState,
      ),
      metadata: AppleAuthMetadata(
        receivedName: credential.receivedName,
        receivedEmail: resolvedEmail != null && resolvedEmail.isNotEmpty,
        capabilities: capabilities,
        createdAt: DateTime.now(),
      ),
      rawCredential: credential,
    );
  }

  /// User identity information (userIdentifier, email, name).
  final AppleAuthIdentity identity;

  /// Authentication tokens (identityToken, authorizationCode, state, nonce).
  final AppleAuthTokens authentication;

  /// Authorization details (granted scopes, realUserStatus).
  final AppleAuthAuthorization authorization;

  /// Lifecycle state (isAuthorized, isFirstAuthorization, native credentialState).
  final AppleAuthLifecycle lifecycle;

  /// Session metadata and platform capability snapshot.
  final AppleAuthMetadata metadata;

  /// Underlying raw [AppleCredential] for full backwards compatibility.
  final AppleCredential rawCredential;

  @override
  String toString() =>
      'AppleAuthSession(identity: $identity, lifecycle: $lifecycle, metadata: $metadata)';
}
