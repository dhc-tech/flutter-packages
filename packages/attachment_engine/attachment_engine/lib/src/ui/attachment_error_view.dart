// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import '../models/attachment_failure.dart';

/// Maps an [AttachmentFailure] to a friendly error UI with a retry button.
class AttachmentErrorView extends StatelessWidget {
  const AttachmentErrorView({super.key, required this.failure, this.onRetry});

  final AttachmentFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(
              failure.localizedMessage,
              textAlign: TextAlign.center,
              key: const Key('attachment_error_message'),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                key: const Key('attachment_error_retry_button'),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
