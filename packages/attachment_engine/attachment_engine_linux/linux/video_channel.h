// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// NOTE: This file has NOT been compiled or verified on this machine (no
// native Linux toolchain / GStreamer+GTK dev headers available here).
// Playback control reuses the same documented GStreamer `playbin` API as
// audio_channel.h/.cc:
//   https://gstreamer.freedesktop.org/documentation/tutorials/basic/playbin-usage.html
//
// Embedding tradeoff (documented, not silently under-delivered): Flutter's
// Linux (GTK) embedder does not expose a stable, public "PlatformView"
// registration API equivalent to Android's `PlatformViewFactory` or iOS's
// `FlutterPlatformView` at the time of writing — GTK platform-view
// compositing on Linux has historically been experimental/unstable across
// Flutter releases. GStreamer's own documented embedding element for GTK,
// `gtksink` (https://gstreamer.freedesktop.org/documentation/gtk/index.html
// — "a GTK widget which is created and returned as a property, that will
// display the video sink's frames"), is used here as the video surface,
// but it is composited as a GTK overlay widget layered on top of the
// `FlView` returned by `fl_plugin_registrar_get_view()`, positioned by
// explicit `setLayout` calls from the Dart-side widget's `RenderBox` — the
// same fallback strategy `video_channel.h`/`.cc` use on Windows. This is
// real, functional embedding, but (like the Windows fallback) sits as a
// separate GTK widget on top of the Flutter scene graph rather than being
// truly composited into it.

#ifndef PACKAGES_ATTACHMENT_ENGINE_LINUX_LINUX_VIDEO_CHANNEL_H_
#define PACKAGES_ATTACHMENT_ENGINE_LINUX_LINUX_VIDEO_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>
#include <glib-object.h>

G_BEGIN_DECLS

#define ATTACHMENT_ENGINE_VIDEO_CHANNEL_TYPE \
  (attachment_engine_video_channel_get_type())
G_DECLARE_FINAL_TYPE(AttachmentEngineVideoChannel, attachment_engine_video_channel,
                      ATTACHMENT_ENGINE, VIDEO_CHANNEL, GObject)

// Replaces `video_player` on Linux. Method channel
// "attachment_engine/video" (load/play/pause/seek/setSpeed/setVolume/
// dispose/setLayout, keyed by `playerId`) plus one EventChannel per player
// at "attachment_engine/video_events/<playerId>" emitting
// `{state, positionMs, durationMs, width, height}` maps — matching
// VideoPlatformView.kt / VideoPlatformView.swift. `setLayout` is the same
// Linux/Windows-only addition documented in the Windows video_channel.h.
AttachmentEngineVideoChannel* attachment_engine_video_channel_new(
    FlBinaryMessenger* messenger, FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // PACKAGES_ATTACHMENT_ENGINE_LINUX_LINUX_VIDEO_CHANNEL_H_
