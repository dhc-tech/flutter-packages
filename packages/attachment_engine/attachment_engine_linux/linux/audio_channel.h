// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// NOTE: This file has NOT been compiled or verified on this machine (no
// native Linux toolchain / GStreamer dev headers available here). Built on
// GStreamer's `playbin` element, documented at:
//   https://gstreamer.freedesktop.org/documentation/tutorials/basic/playbin-usage.html
// `playbin` is GStreamer's own documented "just play this URI" convenience
// element — it auto-builds the demux/decode/sink pipeline internally — and
// is the standard mechanism used by other GTK/GStreamer-based media
// playback integrations for exactly this load/play/pause/seek/rate/volume
// shape.

#ifndef PACKAGES_ATTACHMENT_ENGINE_LINUX_LINUX_AUDIO_CHANNEL_H_
#define PACKAGES_ATTACHMENT_ENGINE_LINUX_LINUX_AUDIO_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>
#include <glib-object.h>

G_BEGIN_DECLS

#define ATTACHMENT_ENGINE_AUDIO_CHANNEL_TYPE \
  (attachment_engine_audio_channel_get_type())
G_DECLARE_FINAL_TYPE(AttachmentEngineAudioChannel, attachment_engine_audio_channel,
                      ATTACHMENT_ENGINE, AUDIO_CHANNEL, GObject)

// Replaces `just_audio` on Linux. Method channel
// "attachment_engine/audio" (load/play/pause/seek/setSpeed/setVolume/
// dispose, keyed by `playerId`) plus one EventChannel per player at
// "attachment_engine/audio_events/<playerId>" emitting
// `{state, positionMs, durationMs}` maps — matching AudioChannel.kt /
// AudioChannel.swift exactly. One `playbin` GStreamer pipeline per
// `playerId`.
AttachmentEngineAudioChannel* attachment_engine_audio_channel_new(
    FlBinaryMessenger* messenger);

G_END_DECLS

#endif  // PACKAGES_ATTACHMENT_ENGINE_LINUX_LINUX_AUDIO_CHANNEL_H_
