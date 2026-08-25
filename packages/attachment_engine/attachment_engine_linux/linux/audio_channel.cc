// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// NOTE: This file has NOT been compiled or verified on this machine — see
// audio_channel.h for the documented GStreamer `playbin` API this is based
// on. The 250ms `g_timeout_add` progress poll mirrors the exact cadence
// used by AudioChannel.kt (Android) and AudioChannel.swift (iOS).

#include "audio_channel.h"

#include <gst/gst.h>

#include <map>
#include <memory>
#include <string>

namespace {
constexpr char kMethodChannelName[] = "attachment_engine/audio";
constexpr char kEventChannelPrefix[] = "attachment_engine/audio_events/";
constexpr guint kProgressTimerMs = 250;
}  // namespace

struct AudioPlayerEntry {
  std::string player_id;
  GstElement* playbin = nullptr;
  FlEventChannel* event_channel = nullptr;
  guint bus_watch_id = 0;
  guint progress_timer_id = 0;
  bool has_listener = false;
};

struct _AttachmentEngineAudioChannel {
  GObject parent_instance;
  FlBinaryMessenger* messenger;  // borrowed
  FlMethodChannel* channel;
  std::map<std::string, std::unique_ptr<AudioPlayerEntry>>* players;
};

G_DEFINE_TYPE(AttachmentEngineAudioChannel, attachment_engine_audio_channel,
              G_TYPE_OBJECT)

static void emit_state(AudioPlayerEntry* entry, const char* state) {
  if (!entry->has_listener) return;
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "state", fl_value_new_string(state));
  fl_event_channel_send(entry->event_channel, map, nullptr, nullptr);
}

static gboolean emit_progress(gpointer user_data) {
  auto* entry = static_cast<AudioPlayerEntry*>(user_data);
  if (!entry->has_listener || !entry->playbin) return G_SOURCE_CONTINUE;

  gint64 position_ns = 0, duration_ns = 0;
  gst_element_query_position(entry->playbin, GST_FORMAT_TIME, &position_ns);
  gst_element_query_duration(entry->playbin, GST_FORMAT_TIME, &duration_ns);

  GstState state = GST_STATE_NULL;
  gst_element_get_state(entry->playbin, &state, nullptr, 0);

  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(
      map, "state",
      fl_value_new_string(state == GST_STATE_PLAYING ? "playing" : "paused"));
  fl_value_set_string_take(
      map, "positionMs",
      fl_value_new_int(static_cast<int64_t>(position_ns / GST_MSECOND)));
  fl_value_set_string_take(
      map, "durationMs",
      fl_value_new_int(static_cast<int64_t>(duration_ns / GST_MSECOND)));
  fl_event_channel_send(entry->event_channel, map, nullptr, nullptr);
  return G_SOURCE_CONTINUE;
}

static gboolean on_bus_message(GstBus*, GstMessage* message,
                                gpointer user_data) {
  auto* entry = static_cast<AudioPlayerEntry*>(user_data);
  switch (GST_MESSAGE_TYPE(message)) {
    case GST_MESSAGE_ASYNC_DONE:
      // First ASYNC_DONE after a state change to PAUSED/PLAYING means
      // preroll completed — the GStreamer analogue of MediaPlayer's
      // `onPrepared`/`CANPLAY`.
      emit_state(entry, "ready");
      if (entry->progress_timer_id == 0) {
        entry->progress_timer_id =
            g_timeout_add(kProgressTimerMs, emit_progress, entry);
      }
      break;
    case GST_MESSAGE_EOS:
      emit_state(entry, "completed");
      break;
    case GST_MESSAGE_ERROR:
      emit_state(entry, "error");
      break;
    default:
      break;
  }
  return TRUE;
}

static AudioPlayerEntry* ensure_entry(AttachmentEngineAudioChannel* self,
                                       const std::string& player_id) {
  auto it = self->players->find(player_id);
  if (it != self->players->end()) return it->second.get();

  auto entry = std::make_unique<AudioPlayerEntry>();
  entry->player_id = player_id;
  entry->playbin = gst_element_factory_make("playbin", nullptr);

  GstBus* bus = gst_element_get_bus(entry->playbin);
  entry->bus_watch_id =
      gst_bus_add_watch(bus, on_bus_message, entry.get());
  gst_object_unref(bus);

  std::string channel_name = kEventChannelPrefix + player_id;
  entry->event_channel = fl_event_channel_new(
      self->messenger, channel_name.c_str(), FL_METHOD_CODEC(fl_standard_method_codec_new()));
  fl_event_channel_set_stream_handlers(
      entry->event_channel,
      [](FlEventChannel*, FlValue*, gpointer user_data) -> FlMethodErrorResponse* {
        static_cast<AudioPlayerEntry*>(user_data)->has_listener = true;
        return nullptr;
      },
      [](FlEventChannel*, FlValue*, gpointer user_data) -> FlMethodErrorResponse* {
        static_cast<AudioPlayerEntry*>(user_data)->has_listener = false;
        return nullptr;
      },
      entry.get(), nullptr);

  auto* raw = entry.get();
  (*self->players)[player_id] = std::move(entry);
  return raw;
}

static void dispose_entry(AttachmentEngineAudioChannel* self,
                           const std::string& player_id) {
  auto it = self->players->find(player_id);
  if (it == self->players->end()) return;
  auto& entry = it->second;
  if (entry->progress_timer_id) g_source_remove(entry->progress_timer_id);
  if (entry->bus_watch_id) g_source_remove(entry->bus_watch_id);
  if (entry->playbin) {
    gst_element_set_state(entry->playbin, GST_STATE_NULL);
    gst_object_unref(entry->playbin);
  }
  self->players->erase(it);
}

static const char* fl_value_get_str_or(FlValue* map, const char* key) {
  FlValue* v = fl_value_lookup_string(map, key);
  return (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
             ? fl_value_get_string(v)
             : nullptr;
}

static void handle_method_call(FlMethodChannel*, FlMethodCall* method_call,
                                gpointer user_data) {
  auto* self = ATTACHMENT_ENGINE_AUDIO_CHANNEL(user_data);
  FlValue* args = fl_method_call_get_args(method_call);
  const char* method = fl_method_call_get_name(method_call);

  const char* player_id_c = fl_value_get_str_or(args, "playerId");
  if (!player_id_c) {
    g_autoptr(FlMethodErrorResponse) response =
        fl_method_error_response_new("bad_args", "playerId is required", nullptr);
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(response), nullptr);
    return;
  }
  std::string player_id = player_id_c;

  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "load") == 0) {
    const char* path = fl_value_get_str_or(args, "path");
    const char* url = fl_value_get_str_or(args, "url");
    AudioPlayerEntry* entry = ensure_entry(self, player_id);
    g_autofree gchar* uri = nullptr;
    if (path) {
      uri = gst_filename_to_uri(path, nullptr);
    } else if (url) {
      uri = g_strdup(url);
    }
    if (uri) g_object_set(entry->playbin, "uri", uri, nullptr);
    emit_state(entry, "buffering");
    gst_element_set_state(entry->playbin, GST_STATE_PAUSED);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "play") == 0) {
    AudioPlayerEntry* entry = ensure_entry(self, player_id);
    gst_element_set_state(entry->playbin, GST_STATE_PLAYING);
    emit_state(entry, "playing");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "pause") == 0) {
    AudioPlayerEntry* entry = ensure_entry(self, player_id);
    gst_element_set_state(entry->playbin, GST_STATE_PAUSED);
    emit_state(entry, "paused");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "seek") == 0) {
    AudioPlayerEntry* entry = ensure_entry(self, player_id);
    FlValue* ms_value = fl_value_lookup_string(args, "positionMs");
    gint64 ms = ms_value ? fl_value_get_int(ms_value) : 0;
    gst_element_seek_simple(
        entry->playbin, GST_FORMAT_TIME,
        static_cast<GstSeekFlags>(GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_KEY_UNIT),
        ms * GST_MSECOND);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setSpeed") == 0) {
    AudioPlayerEntry* entry = ensure_entry(self, player_id);
    FlValue* speed_value = fl_value_lookup_string(args, "speed");
    gdouble speed = speed_value ? fl_value_get_float(speed_value) : 1.0;
    gint64 position_ns = 0;
    gst_element_query_position(entry->playbin, GST_FORMAT_TIME, &position_ns);
    // Rate change via a seek with the same position but a new playback
    // rate, per the documented GStreamer seek-with-rate pattern.
    gst_element_seek(
        entry->playbin, speed, GST_FORMAT_TIME,
        static_cast<GstSeekFlags>(GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_ACCURATE),
        GST_SEEK_TYPE_SET, position_ns, GST_SEEK_TYPE_END, 0);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setVolume") == 0) {
    AudioPlayerEntry* entry = ensure_entry(self, player_id);
    FlValue* volume_value = fl_value_lookup_string(args, "volume");
    gdouble volume = volume_value ? fl_value_get_float(volume_value) : 1.0;
    g_object_set(entry->playbin, "volume", volume, nullptr);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "dispose") == 0) {
    dispose_entry(self, player_id);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void attachment_engine_audio_channel_dispose(GObject* object) {
  auto* self = ATTACHMENT_ENGINE_AUDIO_CHANNEL(object);
  delete self->players;
  self->players = nullptr;
  G_OBJECT_CLASS(attachment_engine_audio_channel_parent_class)->dispose(object);
}

static void attachment_engine_audio_channel_class_init(
    AttachmentEngineAudioChannelClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = attachment_engine_audio_channel_dispose;
}

static void attachment_engine_audio_channel_init(
    AttachmentEngineAudioChannel* self) {
  self->players = new std::map<std::string, std::unique_ptr<AudioPlayerEntry>>();
}

AttachmentEngineAudioChannel* attachment_engine_audio_channel_new(
    FlBinaryMessenger* messenger) {
  gst_init(nullptr, nullptr);

  AttachmentEngineAudioChannel* self = ATTACHMENT_ENGINE_AUDIO_CHANNEL(
      g_object_new(ATTACHMENT_ENGINE_AUDIO_CHANNEL_TYPE, nullptr));
  self->messenger = messenger;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(messenger, kMethodChannelName,
                                         FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, handle_method_call,
                                             self, nullptr);
  return self;
}
