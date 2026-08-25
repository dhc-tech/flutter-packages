// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// NOTE: This file has NOT been compiled or verified on this machine (no
// native Windows toolchain available here). Playback control reuses the
// same documented `IMFMediaEngine` API as audio_channel.h/.cpp:
//   https://learn.microsoft.com/en-us/windows/win32/api/mfmediaengine/nn-mfmediaengine-imfmediaengine
//   https://learn.microsoft.com/en-us/windows/win32/medfound/media-engine
//
// Embedding tradeoff (documented, not silently under-delivered): Media
// Foundation's `IMFMediaEngine` supports two video output modes —
// (a) "frame-server" mode, where the app calls
// `IMFMediaEngineEx::TransferVideoFrame` into a caller-owned Direct3D
// surface/texture on every frame and is responsible for compositing it
// (the shape that would be needed for a true Flutter `Texture`/platform
// view via `flutter::TextureRegistrar` + a DXGI shared surface), and
// (b) simple "render" mode, where the engine draws directly to a target
// HWND via the `MF_MEDIA_ENGINE_PLAYBACK_HWND` creation attribute. This
// first pass uses (b): a native child HWND is created and handed to the
// media engine, and the Dart-side `videoBuildView` widget reports its
// on-screen bounds over the `attachment_engine/video` channel so the child
// HWND can be moved/resized to track it. This is simpler and
// fully-documented, but is NOT proper Flutter compositing — the video
// surface is a real Win32 child window sitting on top of the Flutter
// surface, so it will not participate in Flutter-side transforms,
// opacity, or being drawn *under* other Flutter widgets. A frame-server +
// `flutter::TextureRegistrar` implementation would fix that and is the
// documented follow-up (option (a) above).

#ifndef PACKAGES_ATTACHMENT_ENGINE_WINDOWS_WINDOWS_VIDEO_CHANNEL_H_
#define PACKAGES_ATTACHMENT_ENGINE_WINDOWS_WINDOWS_VIDEO_CHANNEL_H_

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <mfmediaengine.h>
#include <windows.h>
#include <wrl/client.h>

#include <map>
#include <memory>
#include <string>

namespace attachment_engine_windows {

class VideoPlayerEntry;

// Replaces `video_player` on Windows. Method channel
// "attachment_engine/video" (load/play/pause/seek/setSpeed/setVolume/
// dispose/setLayout, keyed by `playerId`) plus one EventChannel per player
// at "attachment_engine/video_events/<playerId>" emitting
// `{state, positionMs, durationMs, width, height}` maps — matching
// VideoPlatformView.kt / VideoPlatformView.swift.
//
// `setLayout` (`{playerId, left, top, width, height}`, in physical pixels)
// is an addition not present in the Android/iOS control-channel surface
// because those platforms embed video through a real
// `PlatformView`/`FlutterPlatformView` that Flutter already positions;
// this HWND-render-mode fallback (see video_channel.h header comment)
// needs an explicit way to keep its child window aligned with the
// Dart-side widget's bounds, so `videoBuildView`'s widget reports them
// here on every layout pass.
class VideoChannel {
 public:
  VideoChannel(flutter::PluginRegistrarWindows* registrar,
               HWND top_level_window);
  ~VideoChannel();

  VideoChannel(const VideoChannel&) = delete;
  VideoChannel& operator=(const VideoChannel&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  VideoPlayerEntry* EnsureEntry(const std::string& player_id);
  void DisposeEntry(const std::string& player_id);

  flutter::PluginRegistrarWindows* registrar_;
  HWND top_level_window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::map<std::string, std::unique_ptr<VideoPlayerEntry>> players_;
};

}  // namespace attachment_engine_windows

#endif  // PACKAGES_ATTACHMENT_ENGINE_WINDOWS_WINDOWS_VIDEO_CHANNEL_H_
