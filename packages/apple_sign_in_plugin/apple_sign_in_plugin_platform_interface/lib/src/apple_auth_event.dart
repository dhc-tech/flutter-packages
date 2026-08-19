// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

import 'apple_credential.dart';

/// Represents high-level authentication lifecycle events.
enum AppleAuthEventType {
  /// A user has successfully completed Sign in with Apple.
  signedIn,

  /// The user signed out locally from the application session.
  signedOut,

  /// The Apple ID credential was revoked by the user via Apple ID settings.
  credentialRevoked,

  /// The app was transferred between developer teams; identifier migration is needed.
  credentialTransferred,

  /// The user dismissed or cancelled the authorization sheet/window.
  authorizationCancelled,

  /// The authentication session changed.
  sessionChanged,
}

/// A strongly-typed authentication lifecycle event.
@immutable
class AppleAuthEvent {
  /// Creates an [AppleAuthEvent].
  const AppleAuthEvent({
    required this.type,
    this.credential,
    this.userIdentifier,
    this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? const _DefaultDateTime();

  /// The type of the authentication lifecycle event.
  final AppleAuthEventType type;

  /// The credential associated with the event, if available (e.g. on [AppleAuthEventType.signedIn]).
  final AppleCredential? credential;

  /// The user identifier associated with the event.
  final String? userIdentifier;

  /// Optional contextual message.
  final String? message;

  /// Timestamp when the event occurred.
  final DateTime timestamp;

  @override
  String toString() =>
      'AppleAuthEvent(type: $type, userIdentifier: $userIdentifier, message: $message)';
}

class _DefaultDateTime implements DateTime {
  const _DefaultDateTime();
  DateTime get _now => DateTime.now();

  @override
  bool isAfter(DateTime other) => _now.isAfter(other);
  @override
  bool isBefore(DateTime other) => _now.isBefore(other);
  @override
  bool isAtSameMomentAs(DateTime other) => _now.isAtSameMomentAs(other);
  @override
  int compareTo(DateTime other) => _now.compareTo(other);
  @override
  int get millisecondsSinceEpoch => _now.millisecondsSinceEpoch;
  @override
  int get microsecondsSinceEpoch => _now.microsecondsSinceEpoch;
  @override
  String get timeZoneName => _now.timeZoneName;
  @override
  Duration get timeZoneOffset => _now.timeZoneOffset;
  @override
  DateTime add(Duration duration) => _now.add(duration);
  @override
  DateTime subtract(Duration duration) => _now.subtract(duration);
  @override
  Duration difference(DateTime other) => _now.difference(other);
  @override
  String toIso8601String() => _now.toIso8601String();
  @override
  DateTime toLocal() => _now.toLocal();
  @override
  DateTime toUtc() => _now.toUtc();
  @override
  int get year => _now.year;
  @override
  int get month => _now.month;
  @override
  int get day => _now.day;
  @override
  int get hour => _now.hour;
  @override
  int get minute => _now.minute;
  @override
  int get second => _now.second;
  @override
  int get millisecond => _now.millisecond;
  @override
  int get microsecond => _now.microsecond;
  @override
  int get weekday => _now.weekday;
  @override
  bool get isUtc => _now.isUtc;
}
