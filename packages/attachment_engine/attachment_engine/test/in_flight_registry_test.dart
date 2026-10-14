// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('N concurrent calls for the same key trigger exactly one underlying operation', () async {
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
  });

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

  test('an old operation finishing after clear() does not drop a newer one for the same key', () async {
    final registry = InFlightRegistry<int>();
    final first = Completer<int>();
    final second = Completer<int>();

    final f1 = registry.run('k', () => first.future);
    registry.clear();
    final f2 = registry.run('k', () => second.future);

    first.complete(1);
    await f1;
    expect(
      registry.isInFlight('k'),
      isTrue,
      reason: 'the newer operation is still running',
    );

    var started = 0;
    final f3 = registry.run('k', () async {
      started++;
      return 3;
    });
    expect(
      identical(f3, f2),
      isTrue,
      reason: 'callers still share the newer operation',
    );
    expect(started, 0);

    second.complete(2);
    expect(await f3, 2);
    expect(registry.isInFlight('k'), isFalse);
  });
}
