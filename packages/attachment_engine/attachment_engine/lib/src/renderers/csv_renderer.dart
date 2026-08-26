// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter/material.dart';

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
  const CsvAttachmentRenderer({this.maxRenderedRows});

  /// Caps how many parsed rows are actually built as table rows, showing a
  /// "showing first N of total" notice above the table when the file has
  /// more rows than this. `Table` builds every row's widget subtree
  /// eagerly (it has no lazy/virtualized builder API), so a very large
  /// CSV/TSV can mean a very large widget tree — this is an opt-in guard
  /// against that.
  ///
  /// Defaults to null: unlimited, every row is rendered. Pass a value
  /// (e.g. `5000`) if you expect files large enough that this matters for
  /// your users.
  final int? maxRenderedRows;

  @override
  AttachmentType get type => .csv;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    return _CsvView(attachment: attachment, maxRenderedRows: maxRenderedRows);
  }

  /// Reads and parses [attachment]'s file, propagating any I/O or parse
  /// failure to the caller (a [FutureBuilder]) rather than swallowing it
  /// into an empty (and indistinguishable from a genuinely-empty file)
  /// result.
  static Future<List<List<String>>> _readRows(
    Attachment attachment,
    String delimiter,
  ) async {
    final path = attachment.localPath;
    if (path == null) {
      throw const FileSystemException('No local file to read.');
    }
    final content = await File(path).readAsString();
    return parseCsv(content, delimiter: delimiter);
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

class _CsvView extends StatefulWidget {
  const _CsvView({required this.attachment, this.maxRenderedRows});
  final Attachment attachment;
  final int? maxRenderedRows;

  @override
  State<_CsvView> createState() => _CsvViewState();
}

class _CsvViewState extends State<_CsvView> {
  late Future<List<List<String>>> _rows;
  late String _delimiter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_CsvView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A parent may reuse this same renderer/widget for a different
    // attachment (e.g. RendererRegistry reusing a CsvAttachmentRenderer
    // instance across CSV files); without this, the previous file's rows
    // would keep showing instead of reloading the new one.
    if (oldWidget.attachment.localPath != widget.attachment.localPath) {
      _load();
    }
  }

  void _load() {
    _delimiter = widget.attachment.extension?.toLowerCase() == 'tsv'
        ? '\t'
        : ',';
    setState(() {
      _rows = CsvAttachmentRenderer._readRows(widget.attachment, _delimiter);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<String>>>(
      future: _rows,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final label = _delimiter == '\t' ? 'TSV' : 'CSV';
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Unable to read this $label file'),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => setState(_load),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicatorPlaceholder());
        }
        final allRows = snapshot.data!;
        if (allRows.isEmpty) {
          return Center(
            child: Text('${_delimiter == '\t' ? 'TSV' : 'CSV'} file is empty'),
          );
        }
        final cap = widget.maxRenderedRows;
        final truncated = cap != null && allRows.length > cap;
        final rows = truncated ? allRows.take(cap).toList() : allRows;
        final columnCount = rows
            .map((r) => r.length)
            .reduce((a, b) => a > b ? a : b);
        return Column(
          children: [
            if (truncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  'Showing the first $cap of ${allRows.length} rows.',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
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
              ),
            ),
          ],
        );
      },
    );
  }
}
