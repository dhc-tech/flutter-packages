// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import '../models/attachment.dart';
import '../models/attachment_type.dart';
import '../native/native_audio_channel.dart'
    show NativePlaybackState, NativePlaybackStatus;
import '../native/native_video_channel.dart';
import 'renderer.dart';

/// Shared pool of [NativeVideoController]s keyed by source, so navigating
/// to the same video twice reuses (rather than duplicates) a controller,
/// and controllers are always disposed exactly once.
class VideoControllerPool {
  VideoControllerPool._();
  static final VideoControllerPool instance = VideoControllerPool._();

  final Map<String, NativeVideoController> _controllers = {};
  final Map<String, int> _refCounts = {};

  NativeVideoController acquire(String key, {String? filePath, String? url}) {
    final existing = _controllers[key];
    if (existing != null) {
      _refCounts[key] = (_refCounts[key] ?? 0) + 1;
      return existing;
    }
    final controller = NativeVideoController();
    controller.load(filePath: filePath, url: filePath == null ? url : null);
    _controllers[key] = controller;
    _refCounts[key] = 1;
    return controller;
  }

  void release(String key) {
    final count = (_refCounts[key] ?? 1) - 1;
    if (count <= 0) {
      _refCounts.remove(key);
      _controllers.remove(key)?.dispose();
    } else {
      _refCounts[key] = count;
    }
  }
}

class VideoAttachmentRenderer extends AttachmentRenderer {
  const VideoAttachmentRenderer();

  @override
  AttachmentType get type => .video;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    return _VideoView(attachment: attachment);
  }
}

class _VideoView extends StatefulWidget {
  const _VideoView({required this.attachment});
  final Attachment attachment;

  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  late final String _key;
  late final NativeVideoController _controller;
  NativePlaybackStatus _status = NativePlaybackStatus.initial();

  @override
  void initState() {
    super.initState();
    _key = widget.attachment.stableIdentity;
    _controller = VideoControllerPool.instance.acquire(
      _key,
      filePath: widget.attachment.localPath,
      url: widget.attachment.localPath == null
          ? widget.attachment.remoteUrl
          : null,
    );
    _controller.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
  }

  @override
  void dispose() {
    VideoControllerPool.instance.release(_key);
    super.dispose();
  }

  /// Reloads the same source into the existing controller — same
  /// filePath/url precedence [VideoControllerPool.acquire] used originally
  /// (local file wins when present, otherwise the remote URL).
  Future<void> _retry() async {
    try {
      await _controller.load(
        filePath: widget.attachment.localPath,
        url: widget.attachment.localPath == null
            ? widget.attachment.remoteUrl
            : null,
      );
    } catch (_) {
      // Playback errors surface via the status stream's error state above.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Checked first and exclusively: a failed load must never fall through
    // to the "assume playable" branch below, which would render the native
    // surface with an uninitialized aspect ratio and no indication anything
    // went wrong — exactly the "stuck on an infinite spinner with no error
    // or retry" bug this branch exists to fix.
    if (_status.state == NativePlaybackState.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            const Text('This video could not be played.'),
            const SizedBox(height: 12),
            TextButton(onPressed: _retry, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_status.state == NativePlaybackState.idle ||
        _status.state == NativePlaybackState.buffering) {
      return Stack(
        alignment: Alignment.center,
        children: [_controller.buildView(), const CircularProgressIndicator()],
      );
    }
    return AspectRatio(
      aspectRatio: _controller.aspectRatio,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          _controller.buildView(),
          Positioned(
            bottom: 24,
            child: IconButton(
              icon: Icon(
                _controller.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
              onPressed: () {
                _controller.isPlaying
                    ? _controller.pause()
                    : _controller.play();
              },
            ),
          ),
        ],
      ),
    );
  }
}
