// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// Deduplicates concurrent operations that share the same logical key
/// (e.g. `Attachment.stableIdentity`) so that N simultaneous callers
/// requesting the same attachment trigger exactly one underlying
/// operation, with every caller awaiting the same shared [Future].
class InFlightRegistry<T> {
  final Map<String, Future<T>> _inFlight = {};

  /// Number of currently in-flight operations. Exposed for tests/diagnostics.
  int get activeCount => _inFlight.length;

  /// Runs [operation] for [key] unless one is already in flight, in which
  /// case the existing future is returned/awaited instead.
  Future<T> run(String key, Future<T> Function() operation) {
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = operation().whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  bool isInFlight(String key) => _inFlight.containsKey(key);

  void clear() => _inFlight.clear();
}
