// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Attachment csvAttachment(String localPath, {String extension = 'csv'}) =>
      Attachment(
        id: 'sample-csv',
        name: 'sample.$extension',
        source: AttachmentSource.url('https://example.com/sample.$extension'),
        extension: extension,
        localPath: localPath,
      );

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('csv_renderer_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('CsvAttachmentRenderer.parseCsv', () {
    test('parses simple comma-separated rows', () {
      final rows = CsvAttachmentRenderer.parseCsv('a,b,c\n1,2,3\n');
      expect(rows, [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('honors quoted fields containing commas', () {
      final rows = CsvAttachmentRenderer.parseCsv(
        'name,note\n"Doe, Jane","says ""hi"""\n',
      );
      expect(rows, [
        ['name', 'note'],
        ['Doe, Jane', 'says "hi"'],
      ]);
    });

    test('handles a trailing row without a final newline', () {
      final rows = CsvAttachmentRenderer.parseCsv('a,b\n1,2');
      expect(rows, [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('returns empty list for empty content', () {
      expect(CsvAttachmentRenderer.parseCsv(''), isEmpty);
    });

    test('parses tab-separated rows when delimiter is tab', () {
      final rows = CsvAttachmentRenderer.parseCsv(
        'a\tb\tc\n1\t2\t3\n',
        delimiter: '\t',
      );
      expect(rows, [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });
  });

  group('CsvAttachmentRenderer.build', () {
    // The renderer reads the resolved file via real `dart:io` File I/O
    // inside a FutureBuilder. The default test binding runs on a fake
    // clock, so real I/O never completes unless the whole
    // pump-build-settle cycle runs inside `tester.runAsync`.
    testWidgets('renders parsed rows as a table', (tester) async {
      final file = File('${tempDir.path}/sample.csv');
      file.writeAsStringSync('name,age\nAda,36\nAlan,41\n');
      const renderer = CsvAttachmentRenderer();

      await tester.runAsync(() async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) =>
                  renderer.build(context, csvAttachment(file.path)),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });

      expect(find.text('name'), findsOneWidget);
      expect(find.text('age'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('41'), findsOneWidget);
    });

    testWidgets('shows an empty-state message for an empty file', (
      tester,
    ) async {
      final file = File('${tempDir.path}/empty.csv');
      file.writeAsStringSync('');
      const renderer = CsvAttachmentRenderer();

      await tester.runAsync(() async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) =>
                  renderer.build(context, csvAttachment(file.path)),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });

      expect(find.text('CSV file is empty'), findsOneWidget);
    });

    testWidgets('renders a .tsv file using tab as the delimiter', (
      tester,
    ) async {
      final file = File('${tempDir.path}/sample.tsv');
      file.writeAsStringSync('name\tage\nAda\t36\n');
      const renderer = CsvAttachmentRenderer();

      await tester.runAsync(() async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => renderer.build(
                context,
                csvAttachment(file.path, extension: 'tsv'),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });

      expect(find.text('name'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('36'), findsOneWidget);
    });
  });
}
