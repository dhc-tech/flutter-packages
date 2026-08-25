// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// NOTE: This file has NOT been compiled or verified on this machine (no
// native Windows toolchain available here). It targets the Media
// Foundation `IMFMediaEngine` API, documented at:
//   https://learn.microsoft.com/en-us/windows/win32/api/mfmediaengine/nn-mfmediaengine-imfmediaengine
//   https://learn.microsoft.com/en-us/windows/win32/api/mfmediaengine/nn-mfmediaengine-imfmediaenginenotify
//   https://learn.microsoft.com/en-us/windows/win32/medfound/media-engine
// `IMFMediaEngine` is Microsoft's own documented, modern, high-level
// playback API (the same engine that backs `<audio>`/`<video>` in Microsoft
// Edge's old EdgeHTML/Trident-based surfaces and is the officially
// recommended replacement for the legacy Media Session API for simple
// load/play/pause/seek/rate/volume playback), created via
// `MFCreateMediaEngineClassFactory` ->
// `IMFMediaEngineClassFactory::CreateInstance`, fed a `MF_MEDIA_ENGINE_*`
// attribute set (including an `IMFMediaEngineNotify` callback for
// `MF_MEDIA_ENGINE_EVENT_*` playback events), and driven with `SetSource`,
// `Play`, `Pause`, `SetCurrentTime`/`GetCurrentTime`, `GetDuration`,
// `SetPlaybackRate`, `SetVolume`, and `Shutdown`.

#ifndef PACKAGES_ATTACHMENT_ENGINE_WINDOWS_WINDOWS_AUDIO_CHANNEL_H_
#define PACKAGES_ATTACHMENT_ENGINE_WINDOWS_WINDOWS_AUDIO_CHANNEL_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <mfmediaengine.h>
#include <windows.h>
#include <wrl/client.h>
#include <wrl/implements.h>

#include <map>
#include <memory>
#include <string>

namespace attachment_engine_windows {

// One IMFMediaEngine instance + its EventChannel, keyed by playerId.
class AudioPlayerEntry;

// Replaces `just_audio` on Windows. Method channel
// "attachment_engine/audio" (load/play/pause/seek/setSpeed/setVolume/
// dispose, all keyed by `playerId`) plus one EventChannel per player at
// "attachment_engine/audio_events/<playerId>" emitting
// `{state, positionMs, durationMs}` maps — matching AudioChannel.kt /
// AudioChannel.swift exactly.
class AudioChannel {
 public:
  explicit AudioChannel(flutter::BinaryMessenger* messenger);
  ~AudioChannel();

  AudioChannel(const AudioChannel&) = delete;
  AudioChannel& operator=(const AudioChannel&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  AudioPlayerEntry* EnsureEntry(const std::string& player_id);
  void DisposeEntry(const std::string& player_id);

  flutter::BinaryMessenger* messenger_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::map<std::string, std::unique_ptr<AudioPlayerEntry>> players_;
};

}  // namespace attachment_engine_windows

#endif  // PACKAGES_ATTACHMENT_ENGINE_WINDOWS_WINDOWS_AUDIO_CHANNEL_H_
