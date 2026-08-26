// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter/widgets.dart';

import '../models/attachment.dart';
import '../models/attachment_type.dart';
import 'renderer.dart';
import 'text_renderer.dart' show CircularProgressIndicatorPlaceholder;

/// Full-view CSV/TSV renderer: parses the resolved file and lays it out as
/// a scrollable [Table] (row-and-column grid) rather than dumping raw
/// delimited text, which is how [AttachmentType.csv] used to be rendered
/// before it had its own renderer (it fell back to the plain-text
/// renderer, which just showed the raw file content unparsed).
///
/// `.tsv` files are handled by this same renderer/[AttachmentType] — the
/// delimiter (comma vs. tab) is auto-detected from [Attachment.extension]
/// (falling back to comma when it's absent or unrecognized).
///
/// Parsing is intentionally minimal (handles quoted fields containing the
/// delimiter/newlines via RFC 4180-style double-quote escaping) rather than
/// pulling in a dedicated CSV package, to keep this renderer dependency-free.
class CsvAttachmentRenderer extends AttachmentRenderer {
  const CsvAttachmentRenderer();

  @override
  AttachmentType get type => .csv;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    final delimiter = attachment.extension?.toLowerCase() == 'tsv' ? '\t' : ',';
    return FutureBuilder<List<List<String>>>(
      future: _readRows(attachment, delimiter),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicatorPlaceholder());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return Center(
            child: Text('${delimiter == '\t' ? 'TSV' : 'CSV'} file is empty'),
          );
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

  Future<List<List<String>>> _readRows(
    Attachment attachment,
    String delimiter,
  ) async {
    final path = attachment.localPath;
    if (path == null) return const [];
    try {
      final content = await File(path).readAsString();
      return parseCsv(content, delimiter: delimiter);
    } catch (_) {
      return const [];
    }
  }

  /// Parses [content] as delimited text (comma by default; pass `'\t'` for
  /// TSV), honoring RFC 4180 double-quote escaping for fields containing
  /// the delimiter, newlines, or literal quotes (`""`).
  static List<List<String>> parseCsv(String content, {String delimiter = ','}) {
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
      if (char == '"') {
        inQuotes = true;
        i++;
      } else if (char == delimiter) {
        row.add(field.toString());
        field.clear();
        i++;
      } else if (char == '\r') {
        i++;
      } else if (char == '\n') {
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = [];
        i++;
      } else {
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
