// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// Merges [overrides] over [base], recursively: a key present in both maps
/// merges nested maps together (rather than one wholesale replacing the
/// other) so e.g. declaring one `platforms.android` option in
/// `white_label.yaml` doesn't silently drop the other auto-derived
/// `platforms.android` keys. Any non-map value in [overrides] simply wins
/// over [base]'s value for that key. Neither input is mutated.
Map<String, dynamic> deepMergeMaps(
  Map<String, dynamic> base,
  Map<String, dynamic> overrides,
) {
  final result = Map<String, dynamic>.of(base);
  for (final entry in overrides.entries) {
    final baseValue = result[entry.key];
    final overrideValue = entry.value;
    if (baseValue is Map<String, dynamic> &&
        overrideValue is Map<String, dynamic>) {
      result[entry.key] = deepMergeMaps(baseValue, overrideValue);
    } else {
      result[entry.key] = overrideValue;
    }
  }
  return result;
}

/// Serializes [map] to YAML text — just enough of the format to round-trip
/// what `icons_launcher`/`flutter_native_splash` config files actually use
/// (nested maps, lists, strings, numbers, bools, null), not a general
/// YAML writer. String values are always double-quoted (safe for any
/// string content YAML would otherwise need escaping for, at the cost of
/// slightly more verbose output than a hand-written file); other scalars
/// are written bare.
String mapToYaml(Map<String, dynamic> map, {int indent = 0}) {
  final buffer = StringBuffer();
  final String pad = '  ' * indent;
  for (final entry in map.entries) {
    final value = entry.value;
    if (value is Map<String, dynamic>) {
      buffer.writeln('$pad${entry.key}:');
      buffer.write(mapToYaml(value, indent: indent + 1));
    } else if (value is List) {
      buffer.writeln('$pad${entry.key}:');
      for (final item in value) {
        buffer.writeln('$pad  - ${_scalarToYaml(item)}');
      }
    } else {
      buffer.writeln('$pad${entry.key}: ${_scalarToYaml(value)}');
    }
  }
  return buffer.toString();
}

String _scalarToYaml(dynamic value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  return '"${value.toString().replaceAll('"', r'\"')}"';
}
