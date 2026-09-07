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

  /// H:MM:SS once the duration reaches an hour, MM:SS otherwise — using
  /// `inMinutes.remainder(60)` unconditionally (as an earlier version of
  /// this did) silently drops the hour component for anything an hour or
  /// longer (e.g. 1:05:00 rendered as "05:00").
  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Future<void> _retry() async {
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
  Widget build(BuildContext context) {
    return StreamBuilder<NativePlaybackStatus>(
      stream: _player.statusStream,
      initialData: _player.status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? NativePlaybackStatus.initial();
        if (status.state == NativePlaybackState.error) {
          // Matches the video renderer's recovery behavior — without this,
          // a failed load left the player permanently unusable unless the
          // whole widget was rebuilt externally.
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                const Text('This audio could not be played.'),
                const SizedBox(height: 12),
                TextButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          );
        }
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
            // Position/duration readout — the slider alone doesn't tell a
            // listener how long the track is or how far into it they are.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(status.position)),
                  Text(_formatDuration(total)),
                ],
              ),
            ),
            IconButton(
              iconSize: 48,
              icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
              onPressed: () => playing ? _player.pause() : _player.play(),
            ),
            // Volume lives on the shared controller (see
            // NativeAudioController.volume), not local widget state — so
            // two renderers of the same pooled attachment stay in sync
            // instead of one showing a stale slider after the other moves
            // it.
            ValueListenableBuilder<double>(
              valueListenable: _player.volume,
              builder: (context, volume, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(volume == 0 ? Icons.volume_off : Icons.volume_up),
                    Expanded(
                      child: Slider(
                        value: volume,
                        onChanged: _player.setVolume,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
