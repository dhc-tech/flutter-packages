// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter/widgets.dart';

import '../models/attachment.dart';
import '../models/attachment_type.dart';
import 'renderer.dart';
import 'text_renderer.dart' show CircularProgressIndicatorPlaceholder;

/// Full-view CSV renderer: parses the resolved file and lays it out as a
/// scrollable [Table] (row-and-column grid) rather than dumping raw
/// comma-separated text, which is how [AttachmentType.csv] used to be
/// rendered before it had its own renderer (it fell back to the plain-text
/// renderer, which just showed the raw file content unparsed).
///
/// Parsing is intentionally minimal (handles quoted fields containing
/// commas/newlines via RFC 4180-style double-quote escaping) rather than
/// pulling in a dedicated CSV package, to keep this renderer dependency-free.
class CsvAttachmentRenderer extends AttachmentRenderer {
  const CsvAttachmentRenderer();

  @override
  AttachmentType get type => AttachmentType.csv;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    return FutureBuilder<List<List<String>>>(
      future: _readRows(attachment),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicatorPlaceholder());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const Center(child: Text('CSV file is empty'));
        }
        final columnCount = rows
            .map((r) => r.length)
            .reduce((a, b) => a > b ? a : b);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: const TableBorder.symmetric(
                inside: BorderSide(color: Color(0x33000000)),
              ),
              children: [
                for (final row in rows)
                  TableRow(
                    children: [
                      for (var i = 0; i < columnCount; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(i < row.length ? row[i] : ''),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<List<String>>> _readRows(Attachment attachment) async {
    final path = attachment.localPath;
    if (path == null) return const [];
    try {
      final content = await File(path).readAsString();
      return parseCsv(content);
    } catch (_) {
      return const [];
    }
  }

  /// Parses [content] as CSV, honoring RFC 4180 double-quote escaping for
  /// fields containing commas, newlines, or literal quotes (`""`).
  static List<List<String>> parseCsv(String content) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var i = 0;
    while (i < content.length) {
      final char = content[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < content.length && content[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        field.write(char);
        i++;
        continue;
      }
      switch (char) {
        case '"':
          inQuotes = true;
          i++;
        case ',':
          row.add(field.toString());
          field.clear();
          i++;
        case '\r':
          i++;
        case '\n':
          row.add(field.toString());
          field.clear();
          rows.add(row);
          row = [];
          i++;
        default:
          field.write(char);
          i++;
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}
