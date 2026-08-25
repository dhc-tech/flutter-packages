// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    AttachmentLocalizations.messageOverride = null;
  });

  group('AttachmentFailure default messages', () {
    test('each failure type has a distinct, non-empty default message', () {
      final failures = <AttachmentFailure>[
        const AttachmentNotFound(),
        const UnsupportedAttachment(),
        const InvalidSource(),
        const NetworkUnavailable(),
        const DownloadFailed(),
        const CacheFailed(),
        const ExpiredUrl(),
        const Unauthorized(),
        const PermissionDenied(),
        const CorruptedFile(),
        const InsufficientStorage(),
        const RendererFailed(),
        const PlaybackFailed(),
        const ConversionFailed(),
        const UnknownFailure(),
      ];

      final messages = failures.map((f) => f.localizedMessage).toSet();
      expect(messages.length, failures.length);
      for (final m in messages) {
        expect(m, isNotEmpty);
      }
    });

    test('equatable equality is based on type and cause', () {
      expect(const AttachmentNotFound(), const AttachmentNotFound());
      expect(
        const AttachmentNotFound(cause: 'x'),
        isNot(const AttachmentNotFound(cause: 'y')),
      );
    });
  });

  group('AttachmentLocalizations override hook', () {
    test('overrides the default message when set', () {
      AttachmentLocalizations.messageOverride = (failure) =>
          failure is NetworkUnavailable ? 'No internet, mate.' : null;

      expect(const NetworkUnavailable().localizedMessage, 'No internet, mate.');
    });

    test('falls back to default when override returns null', () {
      AttachmentLocalizations.messageOverride = (failure) => null;

      expect(
        const DownloadFailed().localizedMessage,
        'The attachment failed to download.',
      );
    });
  });
}
