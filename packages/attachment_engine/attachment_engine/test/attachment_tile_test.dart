import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _attachment = Attachment(
  id: 'a1',
  name: 'Report.pdf',
  source: AttachmentSource.url('https://example.com/report.pdf'),
  attachmentType: AttachmentType.pdf,
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AttachmentTile', () {
    testWidgets('renders name and ready state by default', (tester) async {
      await tester.pumpWidget(
        _wrap(const AttachmentTile(attachment: _attachment)),
      );

      expect(find.text('Report.pdf'), findsOneWidget);
      expect(find.byKey(const Key('attachment_tile_ready')), findsOneWidget);
      expect(find.byKey(const Key('attachment_tile_loading')), findsNothing);
      expect(find.byKey(const Key('attachment_tile_error_icon')), findsNothing);
    });

    testWidgets('renders a loading indicator when isLoading is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const AttachmentTile(attachment: _attachment, isLoading: true)),
      );

      expect(find.byKey(const Key('attachment_tile_loading')), findsOneWidget);
      expect(find.byKey(const Key('attachment_tile_ready')), findsNothing);
    });

    testWidgets('renders an error state with the failure message', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AttachmentTile(
            attachment: _attachment,
            failure: NetworkUnavailable(),
          ),
        ),
      );

      expect(
        find.byKey(const Key('attachment_tile_error_icon')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('attachment_tile_error_text')),
        findsOneWidget,
      );
      expect(find.text('No network connection is available.'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          AttachmentTile(attachment: _attachment, onTap: () => tapped = true),
        ),
      );

      await tester.tap(find.byKey(const Key('attachment_tile')));
      expect(tapped, isTrue);
    });
  });
}
