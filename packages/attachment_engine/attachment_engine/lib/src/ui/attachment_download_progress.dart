import 'package:flutter/material.dart';

import '../download/download_manager.dart';

/// Displays download progress for an attachment as a linear progress bar,
/// listening to a [DownloadManager.progressStream].
class AttachmentDownloadProgress extends StatelessWidget {
  const AttachmentDownloadProgress({super.key, required this.stream});

  final Stream<DownloadProgress> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DownloadProgress>(
      stream: stream,
      builder: (context, snapshot) {
        final progress = snapshot.data;
        return LinearProgressIndicator(value: progress?.fraction);
      },
    );
  }
}
