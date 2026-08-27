// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Chunk size used by every helper below: 64 KB. Large enough that the
/// per-read overhead is negligible, small enough to keep any one read off
/// the event loop briefly rather than blocking on an arbitrarily large
/// file in one call.
const chunkedReadBufferSize = 65536;

/// Reads [path] fully into memory, one [chunkedReadBufferSize] chunk at a
/// time via [RandomAccessFile.read], instead of `File.readAsBytes()`'s
/// single unbounded read (or the synchronous, event-loop-blocking
/// `readAsBytesSync()`).
///
/// The end result is the same complete [Uint8List] either way — this
/// doesn't reduce the final memory footprint (the whole file still has to
/// be held at once for callers that need it as one buffer) — but reading
/// in bounded steps keeps each individual read fast and interruptible
/// rather than one large, unbounded I/O call.
Future<Uint8List> readFileInChunks(
  String path, {
  int chunkSize = chunkedReadBufferSize,
}) async {
  final raf = await File(path).open();
  try {
    final length = await raf.length();
    final result = Uint8List(length);
    var offset = 0;
    while (offset < length) {
      final chunk = await raf.read(chunkSize);
      if (chunk.isEmpty) break; // Shouldn't happen, but avoid looping forever.
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  } finally {
    await raf.close();
  }
}

/// Reads [path] and base64-encodes it, [chunkedReadBufferSize] bytes at a
/// time, without ever materializing the whole raw byte buffer at once —
/// only the (base64, ~1.33x larger) encoded output accumulates. For a
/// large file, this avoids a moment where both the full raw bytes and the
/// full encoded string are held in memory simultaneously, which
/// `base64Encode(await file.readAsBytes())` cannot avoid.
Future<String> readFileAsBase64Chunked(
  String path, {
  int chunkSize = chunkedReadBufferSize,
}) async {
  final output = StringBuffer();
  final sink = ChunkedConversionSink<String>.withCallback(
    (chunks) => chunks.forEach(output.write),
  );
  final base64Sink = base64.encoder.startChunkedConversion(sink);
  final raf = await File(path).open();
  try {
    while (true) {
      final chunk = await raf.read(chunkSize);
      if (chunk.isEmpty) break;
      base64Sink.add(chunk);
    }
  } finally {
    await raf.close();
  }
  base64Sink.close();
  return output.toString();
}

/// Reads at most [maxBytes] from the start of [path], decoded as UTF-8
/// (tolerating a truncated multi-byte sequence at the cut-off point).
/// Meant for previews/snippets that only display a short excerpt — no
/// reason to read (or hold in memory) an entire large file just to show
/// its first few hundred characters.
Future<String> readTextSnippet(
  String path, {
  int maxBytes = chunkedReadBufferSize,
}) async {
  final raf = await File(path).open();
  try {
    final chunk = await raf.read(maxBytes);
    return utf8.decode(chunk, allowMalformed: true);
  } finally {
    await raf.close();
  }
}
