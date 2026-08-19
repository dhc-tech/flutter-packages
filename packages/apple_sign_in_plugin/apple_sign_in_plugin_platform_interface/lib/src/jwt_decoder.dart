import 'dart:convert';

/// Utility for decoding and inspecting the *contents* of a JSON Web Token
/// (JWT), such as an Apple identity token, for display/debugging purposes.
///
/// **This does not verify the token's signature.** It must never be used
/// as a substitute for backend-side identity verification — see the
/// package README's "Backend Boundary" section. Treat any claim read
/// through this class as untrusted until your backend has verified it
/// against Apple's public keys.
class JwtDecoder {
  /// Decode a string JWT token into a `Map<String, dynamic>`
  /// containing the decoded JSON payload.
  ///
  /// Note: header and signature are not returned by this method.
  ///
  /// Throws [FormatException] if parameter is not a valid JWT token.
  static Map<String, dynamic> decode(String token) {
    final List<String> splitToken = token.split('.'); // Split the token by '.'
    if (splitToken.length != 3) {
      throw const FormatException('Invalid token');
    }
    try {
      final String payloadBase64 =
          splitToken[1]; // Payload is always the index 1
      // Base64 should be multiple of 4. Normalize the payload before decode it
      final String normalizedPayload = base64.normalize(payloadBase64);
      // Decode payload, the result is a String
      final String payloadString =
          utf8.decode(base64.decode(normalizedPayload));
      // Parse the String to a Map<String, dynamic>
      final decodedPayload = jsonDecode(payloadString) as Map<String, dynamic>;

      // Return the decoded payload
      return decodedPayload;
    } catch (error) {
      throw const FormatException('Invalid payload');
    }
  }

  /// Decode a string JWT token into a `Map<String, dynamic>`
  /// containing the decoded JSON payload.
  ///
  /// Note: header and signature are not returned by this method.
  ///
  /// Returns null if the token is not valid
  static Map<String, dynamic>? tryDecode(String token) {
    try {
      return decode(token);
    } catch (error) {
      return null;
    }
  }

  /// Tells whether a token is expired.
  ///
  /// Returns false if the token is valid, true if it is expired.
  ///
  /// Throws [FormatException] if parameter is not a valid JWT token.
  static bool isExpired(String token) {
    final DateTime? expirationDate = getExpirationDate(token);
    if (expirationDate == null) {
      return false;
    }
    // If the current date is after the expiration date, the token is already expired
    return DateTime.now().isAfter(expirationDate);
  }

  static DateTime? _getDate({required String token, required String claim}) {
    final Map<String, dynamic> decodedToken = decode(token);
    final expiration = decodedToken[claim] as int?;
    if (expiration == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(expiration * 1000);
  }

  /// Returns token expiration date
  ///
  /// Throws [FormatException] if parameter is not a valid JWT token.
  static DateTime? getExpirationDate(String token) {
    return _getDate(token: token, claim: 'exp');
  }

  /// Returns token issuing date (iat)
  ///
  /// Throws [FormatException] if parameter is not a valid JWT token.
  static Duration? getTokenTime(String token) {
    final DateTime? issuedAtDate = _getDate(token: token, claim: 'iat');
    if (issuedAtDate == null) {
      return null;
    }
    return DateTime.now().difference(issuedAtDate);
  }

  /// Returns remaining time until expiry date.
  ///
  /// Throws [FormatException] if parameter is not a valid JWT token.
  static Duration? getRemainingTime(String token) {
    final DateTime? expirationDate = getExpirationDate(token);
    if (expirationDate == null) {
      return null;
    }

    return expirationDate.difference(DateTime.now());
  }
}
