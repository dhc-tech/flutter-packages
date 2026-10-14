// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:material_ui/material_ui.dart';

/// Shared error visual for every built-in renderer in this package — a
/// circular icon chip over the ambient background, with an optional retry
/// action. Consolidated here (instead of each renderer showing its own bare
/// `Text('...unavailable')`) so every default renderer looks like part of
/// one cohesive package rather than a grab-bag of ad hoc error messages.
/// Deliberately themed off `Theme.of(context)` only — this package ships to
/// every consuming app, so it can't reach for any single app's design
/// system; a consuming app restyling this further does so the same way
/// `AudioAttachmentRenderer` is meant to be restyled — via its own
/// [AttachmentRenderer] registered on `RendererRegistry`.
class RendererErrorState extends StatelessWidget {
  const RendererErrorState({
    required this.message,
    super.key,
    this.onRetry,
    this.icon = Icons.error_outline_rounded,
  });

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: .min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.1),
                shape: .circle,
              ),
              child: Icon(icon, size: 36, color: colorScheme.error),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: .center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: .bold),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
