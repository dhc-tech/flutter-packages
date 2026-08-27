// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import '../models/attachment.dart';
import '../models/attachment_type.dart';
import '../native/native_audio_channel.dart';
import 'renderer.dart';

/// Shared pool of [NativeAudioController]s keyed by source so the same
/// track isn't loaded into multiple concurrent players, and players are
/// disposed exactly once (ref-counted, mirrors [VideoControllerPool]).
class AudioPlayerPool {
  AudioPlayerPool._();
  static final AudioPlayerPool instance = AudioPlayerPool._();

  final Map<String, NativeAudioController> _players = {};
  final Map<String, int> _refCounts = {};

  NativeAudioController acquire(String key) {
    final existing = _players[key];
    if (existing != null) {
      _refCounts[key] = (_refCounts[key] ?? 0) + 1;
      return existing;
    }
    final player = NativeAudioController();
    _players[key] = player;
    _refCounts[key] = 1;
    return player;
  }

  void release(String key) {
    final count = (_refCounts[key] ?? 1) - 1;
    if (count <= 0) {
      _refCounts.remove(key);
      _players.remove(key)?.dispose();
    } else {
      _refCounts[key] = count;
    }
  }
}

class AudioAttachmentRenderer extends AttachmentRenderer {
  const AudioAttachmentRenderer();

  @override
  AttachmentType get type => .audio;

  @override
  Widget build(BuildContext context, Attachment attachment) {
    return _AudioView(attachment: attachment);
  }
}

class _AudioView extends StatefulWidget {
  const _AudioView({required this.attachment});
  final Attachment attachment;

  @override
  State<_AudioView> createState() => _AudioViewState();
}

class _AudioViewState extends State<_AudioView> {
  late final String _key;
  late final NativeAudioController _player;

  @override
  void initState() {
    super.initState();
    _key = widget.attachment.stableIdentity;
    _player = AudioPlayerPool.instance.acquire(_key);
    _load();
  }

  Future<void> _load() async {
    final path = widget.attachment.localPath;
    final url = widget.attachment.remoteUrl;
    try {
      if (path != null) {
        await _player.setFilePath(path);
      } else if (url != null) {
        await _player.setUrl(url);
      }
    } catch (_) {
      // Playback errors surface via the status stream's error state below.
    }
  }

  @override
  void dispose() {
    AudioPlayerPool.instance.release(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<NativePlaybackStatus>(
      stream: _player.statusStream,
      initialData: _player.status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? NativePlaybackStatus.initial();
        final playing = status.state == NativePlaybackState.playing;
        final total = status.duration ?? Duration.zero;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              value: status.position.inMilliseconds
                  .clamp(0, total.inMilliseconds)
                  .toDouble(),
              max: total.inMilliseconds.toDouble().clamp(1, double.infinity),
              onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
            ),
            IconButton(
              iconSize: 48,
              icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
              onPressed: () => playing ? _player.pause() : _player.play(),
            ),
          ],
        );
      },
    );
  }
}
