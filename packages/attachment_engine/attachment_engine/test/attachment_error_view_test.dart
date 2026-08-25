import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AttachmentErrorView', () {
    testWidgets('shows the failure message', (tester) async {
      await tester.pumpWidget(
        _wrap(const AttachmentErrorView(failure: DownloadFailed())),
      );

      expect(find.text('The attachment failed to download.'), findsOneWidget);
    });

    testWidgets('shows a retry button and invokes the callback when tapped', (
      tester,
    ) async {
      var retried = false;
      await tester.pumpWidget(
        _wrap(
          AttachmentErrorView(
            failure: const NetworkUnavailable(),
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(
        find.byKey(const Key('attachment_error_retry_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('attachment_error_retry_button')));
      await tester.pump();

      expect(retried, isTrue);
    });

    testWidgets('does not show a retry button when onRetry is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const AttachmentErrorView(failure: NetworkUnavailable())),
      );

      expect(
        find.byKey(const Key('attachment_error_retry_button')),
        findsNothing,
      );
    });
  });
}
