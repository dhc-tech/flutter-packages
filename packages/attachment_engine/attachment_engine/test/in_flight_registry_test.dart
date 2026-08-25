// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'N concurrent calls for the same key trigger exactly one underlying operation',
    () async {
      final registry = InFlightRegistry<int>();
      var callCount = 0;

      Future<int> underlyingOperation() async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 42;
      }

      final futures = List.generate(
        10,
        (_) => registry.run('key-1', underlyingOperation),
      );
      final results = await Future.wait(futures);

      expect(callCount, 1);
      expect(results, List.filled(10, 42));
      expect(registry.isInFlight('key-1'), isFalse);
    },
  );

  test('different keys run independently', () async {
    final registry = InFlightRegistry<int>();
    var callCount = 0;

    Future<int> op(int value) async {
      callCount++;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return value;
    }

    final results = await Future.wait([
      registry.run('a', () => op(1)),
      registry.run('b', () => op(2)),
    ]);

    expect(callCount, 2);
    expect(results, [1, 2]);
  });

  test('a new call after completion runs the operation again', () async {
    final registry = InFlightRegistry<int>();
    var callCount = 0;
    Future<int> op() async {
      callCount++;
      return callCount;
    }

    final first = await registry.run('key', op);
    final second = await registry.run('key', op);

    expect(first, 1);
    expect(second, 2);
    expect(callCount, 2);
  });
}
