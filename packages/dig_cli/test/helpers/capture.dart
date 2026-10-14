// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';

/// Runs [body] and returns everything it passed to `print`, one entry per call.
Future<List<String>> capturePrints(FutureOr<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    () async => body(),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}
