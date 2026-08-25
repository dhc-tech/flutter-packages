import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

CacheEntry _entry(
  String key,
  int size,
  DateTime lastAccessed, {
  DateTime? expiresAt,
}) {
  return CacheEntry(
    key: key,
    localPath: '/tmp/$key',
    sizeBytes: size,
    createdAt: lastAccessed,
    lastAccessedAt: lastAccessed,
    expiresAt: expiresAt,
  );
}

void main() {
  group('CachePolicy LRU eviction', () {
    test(
      'evicts least-recently-used entries first to satisfy the size cap',
      () {
        const policy = CachePolicy(maxTotalSizeBytes: 100);
        final now = DateTime(2024, 1, 10);
        final entries = [
          _entry('oldest', 40, now.subtract(const Duration(days: 3))),
          _entry('middle', 40, now.subtract(const Duration(days: 2))),
          _entry('newest', 40, now.subtract(const Duration(days: 1))),
        ];

        final toEvict = policy.selectEntriesToEvict(entries);

        expect(toEvict.map((e) => e.key), ['oldest']);
      },
    );

    test('evicts nothing when under the cap', () {
      const policy = CachePolicy(maxTotalSizeBytes: 1000);
      final now = DateTime(2024, 1, 10);
      final entries = [_entry('a', 10, now), _entry('b', 10, now)];

      expect(policy.selectEntriesToEvict(entries), isEmpty);
    });

    test('accounts for incoming bytes when deciding what to evict', () {
      const policy = CachePolicy(maxTotalSizeBytes: 100);
      final now = DateTime(2024, 1, 10);
      final entries = [
        _entry('a', 50, now.subtract(const Duration(days: 2))),
        _entry('b', 40, now.subtract(const Duration(days: 1))),
      ];

      // Existing total 90 + incoming 20 = 110 > 100, so oldest must go.
      final toEvict = policy.selectEntriesToEvict(entries, incomingBytes: 20);

      expect(toEvict.map((e) => e.key), ['a']);
    });

    test('selects expired entries regardless of size', () {
      const policy = CachePolicy(maxTotalSizeBytes: 1000000);
      final now = DateTime.now();
      final entries = [
        _entry(
          'expired',
          1,
          now,
          expiresAt: now.subtract(const Duration(days: 1)),
        ),
        _entry('valid', 1, now, expiresAt: now.add(const Duration(days: 1))),
        _entry('no-expiry', 1, now),
      ];

      final expired = policy.selectExpired(entries);

      expect(expired.map((e) => e.key), ['expired']);
    });
  });
}
