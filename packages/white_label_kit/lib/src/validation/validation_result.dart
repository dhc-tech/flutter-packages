/// Result of a single validation rule. Sealed on purpose so callers must
/// handle both cases — there is no "just a bool", because every failure
/// needs to carry an actionable message (see README's "Errors must be
/// actionable" requirement).
sealed class ValidationResult {
  const ValidationResult();
}

class Valid extends ValidationResult {
  const Valid();
}

class Invalid extends ValidationResult {
  const Invalid(this.message);
  final String message;
}
