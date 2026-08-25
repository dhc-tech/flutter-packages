import 'package:meta/meta.dart';

/// A tiny, dependency-free replacement for the `equatable` package
/// (published by `fluttercommunity.dev` — not `flutter.dev`/`dart.dev`,
/// so it doesn't belong in this repo's dependency graph). Provides the
/// same `props`-based `==`/`hashCode`/`toString` override pattern, using
/// only `dart:core` and `package:meta` (`dart.dev`).
///
/// ```dart
/// class Person extends ValueEquatable {
///   const Person(this.name);
///   final String name;
///
///   @override
///   List<Object?> get props => [name];
/// }
/// ```
@immutable
abstract class ValueEquatable {
  const ValueEquatable();

  /// The list of properties that determine whether two instances are
  /// equal. May contain nested [List]/[Map]/[Set] values — those are
  /// compared and hashed deeply, the same way `equatable` does.
  List<Object?> get props;

  /// If true, [toString] includes [props]. Defaults to false, matching
  /// `equatable`'s own default.
  bool get stringify => false;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ValueEquatable &&
            runtimeType == other.runtimeType &&
            _propsEqual(props, other.props));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, Object.hashAll(props.map(_hashOf)));

  @override
  String toString() {
    if (!stringify) {
      return '$runtimeType';
    }
    return '$runtimeType(${props.map((p) => p.toString()).join(', ')})';
  }
}

bool _propsEqual(List<Object?> a, List<Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_deepEquals(a[i], b[i])) return false;
  }
  return true;
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) return _mapEquals(a, b);
  if (a is List && b is List) return _listEquals(a, b);
  if (a is Set && b is Set) return _setEquals(a, b);
  return a == b;
}

bool _mapEquals(Map<Object?, Object?> a, Map<Object?, Object?> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
  }
  return true;
}

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_deepEquals(a[i], b[i])) return false;
  }
  return true;
}

bool _setEquals(Set<Object?> a, Set<Object?> b) {
  if (a.length != b.length) return false;
  return a.every(b.contains);
}

int _hashOf(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map((e) => Object.hash(_hashOf(e.key), _hashOf(e.value))),
    );
  }
  if (value is Set) {
    return Object.hashAllUnordered(value.map(_hashOf));
  }
  if (value is List) {
    return Object.hashAll(value.map(_hashOf));
  }
  return value.hashCode;
}
