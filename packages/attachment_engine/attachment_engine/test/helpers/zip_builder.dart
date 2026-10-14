// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

/// One entry for [buildZip].
class TestZipEntry {
  const TestZipEntry(
    this.name,
    this.content, {
    this.deflate = false,
    this.symlink = false,
    this.method,
  });

  final String name;
  final List<int> content;

  /// Store the content raw-deflated (method 8) instead of stored (0).
  final bool deflate;

  /// Mark as a unix symlink via the external attributes.
  final bool symlink;

  /// Force an arbitrary compression method id (for unsupported-method tests).
  final int? method;
}

/// Builds a valid zip archive in memory. CRC-32 is left 0: the reader under
/// test does not validate it.
Uint8List buildZip(List<TestZipEntry> entries, {int commentLength = 0}) {
  final out = BytesBuilder();
  void u16(int v) => out.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(int v) =>
      out.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);

  final offsets = <int>[];
  final payloads = <List<int>>[];
  final methods = <int>[];
  for (final e in entries) {
    final data = e.deflate
        ? ZLibEncoder(raw: true, level: 6).convert(e.content)
        : e.content;
    payloads.add(data);
    methods.add(e.method ?? (e.deflate ? 8 : 0));
  }

  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final nameBytes = e.name.codeUnits;
    offsets.add(out.length);
    u32(0x04034b50);
    u16(20);
    u16(0);
    u16(methods[i]);
    u16(0);
    u16(0);
    u32(0);
    u32(payloads[i].length);
    u32(e.content.length);
    u16(nameBytes.length);
    u16(0);
    out.add(nameBytes);
    out.add(payloads[i]);
  }

  final centralStart = out.length;
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final nameBytes = e.name.codeUnits;
    u32(0x02014b50);
    u16(e.symlink ? (3 << 8) | 20 : 20);
    u16(20);
    u16(0);
    u16(methods[i]);
    u16(0);
    u16(0);
    u32(0);
    u32(payloads[i].length);
    u32(e.content.length);
    u16(nameBytes.length);
    u16(0);
    u16(0);
    u16(0);
    u16(0);
    u32(e.symlink ? (0xA1FF << 16) : 0);
    u32(offsets[i]);
    out.add(nameBytes);
  }
  final centralSize = out.length - centralStart;

  u32(0x06054b50);
  u16(0);
  u16(0);
  u16(entries.length);
  u16(entries.length);
  u32(centralSize);
  u32(centralStart);
  u16(commentLength);
  out.add(List<int>.filled(commentLength, 0x20));
  return out.toBytes();
}
