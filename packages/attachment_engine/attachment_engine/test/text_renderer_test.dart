// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Attachment textAttachment(String localPath) => Attachment(
    id: 'sample-text',
    name: 'sample.txt',
    source: const AttachmentSource.url('https://example.com/sample.txt'),
    extension: 'txt',
    localPath: localPath,
  );

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('text_renderer_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpTextView(
    WidgetTester tester,
    String content, {
    TextAttachmentRenderer renderer = const TextAttachmentRenderer(
      showSearch: true,
    ),
  }) async {
    final file = File('${tempDir.path}/sample.txt');
    file.writeAsStringSync(content);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  renderer.build(context, textAttachment(file.path)),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
  }

  group('TextAttachmentRenderer full view', () {
    testWidgets('shows a search field', (tester) async {
      await pumpTextView(tester, 'hello world\nsecond line\n');

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('hello world'), findsOneWidget);
    });

    testWidgets('finds and counts matches across lines', (tester) async {
      await pumpTextView(tester, 'apple pie\nbanana split\napple crumble\n');

      await tester.enterText(find.byType(TextField), 'apple');
      await tester.pump(const Duration(milliseconds: 200)); // past debounce

      expect(find.text('1/2'), findsOneWidget);
    });

    testWidgets(
      'the match count does not update immediately after a keystroke — '
      'only once the debounce delay has actually elapsed',
      (tester) async {
        await pumpTextView(tester, 'apple pie\nbanana split\napple crumble\n');

        await tester.enterText(find.byType(TextField), 'apple');
        await tester.pump(); // no delay — well under the debounce window

        // Search hasn't run yet: no match-count indicator showing "1/2".
        expect(find.text('1/2'), findsNothing);

        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('1/2'), findsOneWidget);
      },
    );

    testWidgets(
      'a burst of keystrokes within the debounce window only searches '
      'once, for the final query — not once per keystroke',
      (tester) async {
        await pumpTextView(tester, 'apple pie\nbanana split\n');

        // Simulates fast typing: each partial query arrives well within
        // the 150ms debounce window of the previous one.
        await tester.enterText(find.byType(TextField), 'a');
        await tester.pump(const Duration(milliseconds: 30));
        await tester.enterText(find.byType(TextField), 'ap');
        await tester.pump(const Duration(milliseconds: 30));
        await tester.enterText(find.byType(TextField), 'app');
        await tester.pump(const Duration(milliseconds: 30));
        await tester.enterText(find.byType(TextField), 'appl');
        await tester.pump(const Duration(milliseconds: 30));
        await tester.enterText(find.byType(TextField), 'apple');

        // None of the intermediate partial queries ever got far enough
        // into their own debounce window to actually run a search.
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('1/1'), findsOneWidget); // final query: "apple"
      },
    );

    testWidgets('next/previous navigation cycles through matches', (
      tester,
    ) async {
      await pumpTextView(tester, 'foo\nfoo\nfoo\n');

      await tester.enterText(find.byType(TextField), 'foo');
      await tester.pump(const Duration(milliseconds: 200)); // past debounce
      expect(find.text('1/3'), findsOneWidget);

      await tester.tap(find.byTooltip('Next match'));
      await tester.pump();
      expect(find.text('2/3'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous match'));
      await tester.pump();
      expect(find.text('1/3'), findsOneWidget);

      // Wraps around backwards from the first match to the last.
      await tester.tap(find.byTooltip('Previous match'));
      await tester.pump();
      expect(find.text('3/3'), findsOneWidget);
    });

    testWidgets('shows 0/0 when the query has no matches', (tester) async {
      await pumpTextView(tester, 'hello world\n');

      await tester.enterText(find.byType(TextField), 'nope');
      await tester.pump(const Duration(milliseconds: 200)); // past debounce

      expect(find.text('0/0'), findsOneWidget);
    });

    testWidgets(
      'a case-fold-expanding character before a match does not throw a '
      'RangeError (offsets must stay valid against the original text, not '
      'a lowercased copy of a different length)',
      (tester) async {
        // İ (Turkish dotted capital I, U+0130) lowercases to a 2-UTF-16-unit
        // sequence ("i" + combining dot above) — one code unit longer than
        // itself. A match for "abc" starting after it would land at the
        // wrong offset if matching were done against a lowercased copy of
        // the line instead of the original.
        await pumpTextView(tester, 'İ abc\n');

        await tester.enterText(find.byType(TextField), 'abc');
        await tester.pump(const Duration(milliseconds: 200)); // past debounce

        expect(tester.takeException(), isNull);
        expect(find.text('1/1'), findsOneWidget);
      },
    );

    testWidgets('showSearch: false renders plain scrollable text', (
      tester,
    ) async {
      await pumpTextView(
        tester,
        'no search bar here\n',
        renderer: const TextAttachmentRenderer(showSearch: false),
      );

      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('no search bar here'), findsOneWidget);
    });

    testWidgets('snippetMode ignores showSearch and shows no search bar', (
      tester,
    ) async {
      await pumpTextView(
        tester,
        'a snippet preview\n',
        renderer: const TextAttachmentRenderer(snippetMode: true),
      );

      expect(find.byType(TextField), findsNothing);
    });

    testWidgets(
      'reusing the same widget for different text reloads its lines and '
      'search results instead of keeping the previous document\'s',
      (tester) async {
        const renderer = TextAttachmentRenderer(showSearch: true);
        final fileA = File('${tempDir.path}/a.txt');
        fileA.writeAsStringSync('apple pie\nbanana split\n');
        final fileB = File('${tempDir.path}/b.txt');
        fileB.writeAsStringSync('completely different content\n');

        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) =>
                      renderer.build(context, textAttachment(fileA.path)),
                ),
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        });
        expect(find.text('apple pie'), findsOneWidget);

        // Search for "apple" while file A is showing, then swap to file B
        // before clearing the query — the stale match count/lines must
        // not survive the swap.
        await tester.enterText(find.byType(TextField), 'apple');
        await tester.pump(const Duration(milliseconds: 200)); // past debounce
        expect(find.text('1/1'), findsOneWidget);

        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) =>
                      renderer.build(context, textAttachment(fileB.path)),
                ),
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
          await tester.pump();
        });

        // findRichText: true — with the "apple" query still active from
        // before the swap, each line renders as Text.rich (for match
        // highlighting) rather than a plain Text.
        expect(
          find.text('completely different content', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('apple pie', findRichText: true), findsNothing);
        // The query text itself is preserved (it's the user's own input,
        // in _searchController — not attachment-specific state), but its
        // match count is recomputed against the new document: "apple"
        // doesn't appear in file B's content at all.
        expect(find.text('0/0'), findsOneWidget);
      },
    );
  });
}
