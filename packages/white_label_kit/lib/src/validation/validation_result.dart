// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// Result of a single validation rule. Sealed on purpose so callers must
/// handle both cases — there is no "just a bool", because every failure
/// needs to carry an actionable message (see README's "Errors must be
/// actionable" requirement).
sealed class ValidationResult {
  const ValidationResult();
}

/// A passing validation outcome.
class Valid extends ValidationResult {
  /// Creates a passing validation outcome.
  const Valid();
}

/// A failing validation outcome carrying an actionable [message].
class Invalid extends ValidationResult {
  /// Creates a failing validation outcome with an actionable [message].
  const Invalid(this.message);

  /// Human-readable, actionable description of why validation failed.
  final String message;
}
