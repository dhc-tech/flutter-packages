// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter/material.dart';

import '../models/attachment.dart';
import '../models/attachment_type.dart';
import 'renderer.dart';

/// Plain text viewer. Set [snippetMode] to true (via [TextAttachmentRenderer.preview])
/// for a short, non-scrolling preview rather than the full document.
///
/// Full (non-snippet) mode includes a search bar (case-insensitive, with
/// match count and next/previous navigation that scrolls to and highlights
/// each match) — set [showSearch] to false to opt out and get the plain
/// scrollable text view instead.
class TextAttachmentRenderer extends AttachmentRenderer {
  const TextAttachmentRenderer({
    this.snippetMode = false,
    this.snippetLength = 280,
    this.showSearch = true,
  });

  final bool snippetMode;
  final int snippetLength;

  /// Whether the full (non-snippet) view shows an in-file search bar.
  /// Ignored when [snippetMode] is true (a 3-line preview has nothing
  /// meaningful to search).
  final bool showSearch;

  @override
  AttachmentType get type => .text;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    return FutureBuilder<String>(
      future: _readText(attachment),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicatorPlaceholder());
        }
        final text = snapshot.data!;
        if (snippetMode) {
          final display = text.length > snippetLength
              ? '${text.substring(0, snippetLength)}…'
              : text;
          return Text(display, maxLines: 3, overflow: TextOverflow.ellipsis);
        }
        if (!showSearch) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(text),
          );
        }
        return _SearchableTextView(text: text);
      },
    );
  }

  Future<String> _readText(Attachment attachment) async {
    final path = attachment.localPath;
    if (path == null) return '';
    try {
      return await File(path).readAsString();
    } catch (_) {
      return '';
    }
  }
}

/// Minimal loading placeholder to avoid pulling in Material just for a spinner.
class CircularProgressIndicatorPlaceholder extends StatelessWidget {
  const CircularProgressIndicatorPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 24, height: 24);
}

/// One occurrence of the search query: which line it's on and the
/// character offset within that line.
class _Match {
  const _Match({required this.lineIndex, required this.columnStart});
  final int lineIndex;
  final int columnStart;
}

/// Full-text viewer with a search bar: case-insensitive substring search
/// across the whole document, a "n / total" match counter, next/previous
/// navigation that scrolls the matched line into view, and inline
/// highlighting (current match distinguished from the rest).
class _SearchableTextView extends StatefulWidget {
  const _SearchableTextView({required this.text});
  final String text;

  @override
  State<_SearchableTextView> createState() => _SearchableTextViewState();
}

class _SearchableTextViewState extends State<_SearchableTextView> {
  // Rough estimate of one unwrapped line's height at the default text
  // style, used only to jump the (lazily-built) ListView roughly into
  // range — [_scrollToCurrentMatch] then fine-corrects against the actual
  // laid-out row once it exists.
  static const _estimatedLineHeight = 20.0;

  late final List<String> _lines = widget.text.split('\n');
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _itemScrollOffsets = <int, GlobalKey>{};

  List<_Match> _matches = [];
  int _currentMatch = -1;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    setState(() {
      _matches = _findMatches(query);
      _currentMatch = _matches.isEmpty ? -1 : 0;
    });
    if (_currentMatch >= 0) _scrollToCurrentMatch();
  }

  List<_Match> _findMatches(String query) {
    if (query.isEmpty) return const [];
    final lowerQuery = query.toLowerCase();
    final matches = <_Match>[];
    for (var i = 0; i < _lines.length; i++) {
      final lowerLine = _lines[i].toLowerCase();
      var start = 0;
      while (true) {
        final index = lowerLine.indexOf(lowerQuery, start);
        if (index == -1) break;
        matches.add(_Match(lineIndex: i, columnStart: index));
        start = index + lowerQuery.length;
      }
    }
    return matches;
  }

  void _goToMatch(int delta) {
    if (_matches.isEmpty) return;
    setState(() {
      _currentMatch = (_currentMatch + delta) % _matches.length;
      if (_currentMatch < 0) _currentMatch += _matches.length;
    });
    _scrollToCurrentMatch();
  }

  void _scrollToCurrentMatch() {
    final match = _matches[_currentMatch];

    // The matched row may be far outside the ListView's build/cache
    // extent (it's lazy), so its GlobalKey has no context yet. Jump to a
    // rough estimated offset first so the row gets built...
    if (_scrollController.hasClients) {
      final estimatedOffset = match.lineIndex * _estimatedLineHeight;
      _scrollController.jumpTo(
        estimatedOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    }

    // ...then, once it has been laid out, fine-correct against its real
    // position so the match lands fully in view regardless of how
    // inaccurate the estimate was.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemScrollOffsets[match.lineIndex];
      final matchContext = key?.currentContext;
      if (matchContext != null) {
        Scrollable.ensureVisible(
          matchContext,
          alignment: 0.3,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onQueryChanged,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Search in document',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (_searchController.text.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  _matches.isEmpty
                      ? '0/0'
                      : '${_currentMatch + 1}/${_matches.length}',
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: 'Previous match',
                  onPressed: _matches.isEmpty ? null : () => _goToMatch(-1),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: 'Next match',
                  onPressed: _matches.isEmpty ? null : () => _goToMatch(1),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _lines.length,
            itemBuilder: (context, index) {
              final key = _itemScrollOffsets.putIfAbsent(
                index,
                () => GlobalKey(),
              );
              return Container(key: key, child: _highlightedLine(index));
            },
          ),
        ),
      ],
    );
  }

  Widget _highlightedLine(int lineIndex) {
    final line = _lines[lineIndex];
    final query = _searchController.text;
    if (query.isEmpty) return Text(line);

    final lowerLine = line.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    while (true) {
      final index = lowerLine.indexOf(lowerQuery, cursor);
      if (index == -1) {
        spans.add(TextSpan(text: line.substring(cursor)));
        break;
      }
      if (index > cursor) {
        spans.add(TextSpan(text: line.substring(cursor, index)));
      }
      final isCurrent =
          _currentMatch >= 0 &&
          _matches[_currentMatch].lineIndex == lineIndex &&
          _matches[_currentMatch].columnStart == index;
      spans.add(
        TextSpan(
          text: line.substring(index, index + query.length),
          style: TextStyle(
            backgroundColor: isCurrent
                ? const Color(0xFFFFA000)
                : const Color(0x66FFEB3B),
          ),
        ),
      );
      cursor = index + query.length;
    }
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: spans,
      ),
    );
  }
}
